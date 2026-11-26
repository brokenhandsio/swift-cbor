// MARK: - Value identity
//
// `==` follows RFC 8949 §5.6.1 map-key equivalence. `hash(into:)` uses the same
// rules and walks nested values without overflowing the stack.
//
// Swift String equality normalizes Unicode, while CBOR text compares UTF-8
// bytes. IEEE equality makes NaN unequal to itself, while CBOR compares NaN
// significands. CBOR also equates signed zero and equal floats of any width.

extension CBOR {
    /// Whether two values are equivalent in the CBOR generic data model.
    ///
    /// Text compares by UTF-8 bytes. Floats compare numerically across widths,
    /// with signed zero equal and NaNs compared by their zero-extended
    /// significands. Equal values can retain different encodings. Nested values
    /// are compared iteratively, so deep comparisons cannot overflow the stack.
    public static func == (lhs: CBOR, rhs: CBOR) -> Bool {
        // Fast path. Scalars are the overwhelming majority of comparisons —
        // every map-key lookup during decoding lands here — so they must not
        // touch the heap. Only the three container cases fall through to the
        // iterative walk below.
        switch (lhs, rhs) {
        case (.unsignedInt(let a), .unsignedInt(let b)): return a == b
        case (.negativeInt(let a), .negativeInt(let b)): return a == b
        case (.byteString(let a), .byteString(let b)): return a == b
        case (.textString(let a), .textString(let b)): return a.utf8.elementsEqual(b.utf8)
        case (.simple(let a), .simple(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.null, .null): return true
        case (.undefined, .undefined): return true
        case (.half, .half), (.half, .float), (.half, .double),
             (.float, .half), (.float, .float), (.float, .double),
             (.double, .half), (.double, .float), (.double, .double):
            return lhs.floatKey == rhs.floatKey
        case (.array, .array), (.map, .map), (.tagged, .tagged):
            return deepEqual(lhs, rhs)
        default:
            return false
        }
    }

    /// Structural comparison of two containers, walked with an explicit stack.
    ///
    /// Native recursion here would be a stack overflow waiting to happen: a
    /// value nested `n` deep costs `n` frames, and `n` is attacker-controlled
    /// up to `CBORDecodingOptions.maximumDepth`, which callers may raise. The parser
    /// and encoder avoid recursion for the same reason, so comparison should
    /// not be the one place that reintroduces the limit.
    private static func deepEqual(_ lhs: CBOR, _ rhs: CBOR) -> Bool {
        var pending: [(CBOR, CBOR)] = [(lhs, rhs)]

        while let (left, right) = pending.popLast() {
            switch (left, right) {
            case (.array(let a), .array(let b)):
                guard a.count == b.count else { return false }
                for index in a.indices {
                    pending.append((a[index], b[index]))
                }
            case (.map(let a), .map(let b)):
                guard a.count == b.count else { return false }
                for (key, value) in a {
                    // Looking the key up in `b` hashes it, which is where key
                    // identity — including float and UTF-8 equivalence —
                    // actually gets applied.
                    guard let other = b[key] else { return false }
                    pending.append((value, other))
                }
            case (.tagged(let tagA, let a), (.tagged(let tagB, let b))):
                guard tagA == tagB else { return false }
                pending.append((a, b))
            default:
                // Scalars and mismatched cases: the fast path above is
                // non-recursive, so this cannot re-enter `deepEqual`.
                guard left == right else { return false }
            }
        }
        return true
    }

    /// Hash the complete value consistently with `==`.
    ///
    /// Containers are walked with an explicit stack. A fixed depth cutoff would
    /// make every key with the same prefix collide, allowing a small CBOR map to
    /// take quadratic time to decode.
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .array, .map, .tagged:
            hasher.combine(deepHash())
        default:
            // Map keys are usually scalars, so they do not need a work stack or
            // an intermediate Hasher.
            hashScalar(into: &hasher)
        }
    }

    /// Finish child hashes before their parent, using O(depth) temporary space.
    /// A map combines pair hashes commutatively because its iteration order is
    /// unspecified; arrays and tags preserve their element order.
    private func deepHash() -> Int {
        var frames: [HashFrame] = []
        var work = HashWork.value(self)

        while true {
            switch work {
            case .value(let value):
                switch value {
                case .array(let elements):
                    var hasher = Hasher()
                    hasher.combine(4 as UInt8)
                    hasher.combine(elements.count)
                    if let first = elements.first {
                        frames.append(.array(elements, next: 1, hasher))
                        work = .value(first)
                    } else {
                        work = .digest(hasher.finalize())
                    }
                case .map(let entries):
                    if entries.isEmpty {
                        var hasher = Hasher()
                        hasher.combine(5 as UInt8)
                        hasher.combine(0)
                        hasher.combine(0)
                        work = .digest(hasher.finalize())
                    } else {
                        let index = entries.startIndex
                        frames.append(.map(entries, index: index, keyDigest: nil, combined: 0))
                        work = .value(entries[index].key)
                    }
                case .tagged(let tag, let item):
                    var hasher = Hasher()
                    hasher.combine(6 as UInt8)
                    hasher.combine(tag)
                    frames.append(.tag(hasher))
                    work = .value(item)
                default:
                    var hasher = Hasher()
                    value.hashScalar(into: &hasher)
                    work = .digest(hasher.finalize())
                }

            case .digest(let digest):
                guard let frame = frames.popLast() else { return digest }
                switch frame {
                case .array(let elements, let next, var hasher):
                    hasher.combine(digest)
                    if next < elements.count {
                        frames.append(.array(elements, next: next + 1, hasher))
                        work = .value(elements[next])
                    } else {
                        work = .digest(hasher.finalize())
                    }
                case .map(let entries, let index, let keyDigest, let combined):
                    if let keyDigest {
                        var pairHasher = Hasher()
                        pairHasher.combine(keyDigest)
                        pairHasher.combine(digest)
                        let updated = combined ^ pairHasher.finalize()
                        let next = entries.index(after: index)
                        if next == entries.endIndex {
                            var hasher = Hasher()
                            hasher.combine(5 as UInt8)
                            hasher.combine(entries.count)
                            hasher.combine(updated)
                            work = .digest(hasher.finalize())
                        } else {
                            frames.append(.map(entries, index: next, keyDigest: nil, combined: updated))
                            work = .value(entries[next].key)
                        }
                    } else {
                        frames.append(.map(entries, index: index, keyDigest: digest, combined: combined))
                        work = .value(entries[index].value)
                    }
                case .tag(var hasher):
                    hasher.combine(digest)
                    work = .digest(hasher.finalize())
                }
            }
        }
    }

    /// Hash a value with no children. All comparisons in the scalar fast path
    /// above have matching cases here, including bytewise text and numeric floats.
    private func hashScalar(into hasher: inout Hasher) {
        switch self {
        case .unsignedInt(let value):
            hasher.combine(0 as UInt8)
            hasher.combine(value)
        case .negativeInt(let value):
            hasher.combine(1 as UInt8)
            hasher.combine(value)
        case .byteString(let value):
            hasher.combine(2 as UInt8)
            hasher.combine(value)
        case .textString(let value):
            hasher.combine(3 as UInt8)
            hasher.combine(value.utf8.count)
            for byte in value.utf8 { hasher.combine(byte) }
        case .simple(let value):
            hasher.combine(7 as UInt8)
            hasher.combine(value)
        case .bool(let value):
            hasher.combine(8 as UInt8)
            hasher.combine(value)
        case .null:
            hasher.combine(9 as UInt8)
        case .undefined:
            hasher.combine(10 as UInt8)
        case .half, .float, .double:
            hasher.combine(11 as UInt8)
            hasher.combine(floatKey)
        case .array, .map, .tagged:
            break // handled by deepHash()
        }
    }

    /// Finite values and infinities convert exactly to Double; NaNs must be
    /// handled from their bits so conversion cannot quiet signaling NaNs.
    private var floatKey: FloatKey {
        switch self {
        case .half(let bits):
            if bits & 0x7c00 == 0x7c00, bits & 0x03ff != 0 {
                return .nan(UInt64(bits & 0x03ff) << 54)
            }
            return .number(HalfPrecision.double(fromBits: bits))
        case .float(let value):
            let bits = value.bitPattern
            if bits & 0x7f80_0000 == 0x7f80_0000, bits & 0x007f_ffff != 0 {
                return .nan(UInt64(bits & 0x007f_ffff) << 41)
            }
            return .number(Double(value))
        case .double(let value):
            let bits = value.bitPattern
            if bits & 0x7ff0_0000_0000_0000 == 0x7ff0_0000_0000_0000,
               bits & 0x000f_ffff_ffff_ffff != 0 {
                return .nan((bits & 0x000f_ffff_ffff_ffff) << 12)
            }
            return .number(value)
        default:
            preconditionFailure("floatKey requires a float")
        }
    }
}

private enum FloatKey: Hashable {
    case number(Double)
    case nan(UInt64)
}

/// The parent waiting for a child hash. Only one child of a container is
/// pending at a time, so hashing a wide array or map uses O(depth) space.
private enum HashFrame {
    case array([CBOR], next: Int, Hasher)
    case map([CBOR: CBOR], index: [CBOR: CBOR].Index, keyDigest: Int?, combined: Int)
    case tag(Hasher)
}

private enum HashWork {
    case value(CBOR)
    case digest(Int)
}
