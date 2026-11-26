// MARK: - Value identity
//
// `==` is written out rather than synthesized so that the three float cases
// compare by bit pattern instead of by IEEE equality. `hash(into:)` is written
// out so that hashing a deeply nested value cannot overflow the stack.
//
// Synthesis would give `.double(.nan) != .double(.nan)`, which is right for
// arithmetic and wrong for a data model. Two CBOR items are the same item when
// they encode to the same bytes, and a NaN payload encodes to exactly itself.
// Under IEEE semantics a `[CBOR: CBOR]` would accept the same NaN key twice —
// the map then holds two entries whose encoded keys are byte-identical, so the
// deterministic key sort (RFC 8949 §4.2.1, bytewise over encoded keys) has no
// total order to work with. The same map could encode two different ways, and
// the output contained a duplicate key, which is not valid deterministic CBOR
// at all. Found by fuzzing; see FloatKeyIdentityTests.
//
// Two consequences worth knowing:
//
// - Distinct NaN payloads stay distinct, because their bit patterns and
//   therefore their encodings differ.
// - `0.0` and `-0.0` are now different keys. They encode differently
//   (`0xfb 0000…` vs `0xfb 8000…`), so collapsing them would reintroduce the
//   same ambiguity from the other direction.

extension CBOR {
    /// Whether two values are the same CBOR data item.
    ///
    /// Floats compare by bit pattern rather than by IEEE 754 equality: a NaN
    /// equals an identical NaN, `0.0` and `-0.0` are different, and ``half(bitPattern:)``,
    /// ``float(_:)`` and ``double(_:)`` never equal one another, even for the same
    /// number. Nested values are compared iteratively, so comparing deeply nested
    /// values cannot overflow the stack.
    public static func == (lhs: CBOR, rhs: CBOR) -> Bool {
        // Fast path. Scalars are the overwhelming majority of comparisons —
        // every map-key lookup during decoding lands here — so they must not
        // touch the heap. Only the three container cases fall through to the
        // iterative walk below.
        switch (lhs, rhs) {
        case (.unsignedInt(let a), .unsignedInt(let b)): return a == b
        case (.negativeInt(let a), .negativeInt(let b)): return a == b
        case (.byteString(let a), .byteString(let b)): return a == b
        case (.textString(let a), .textString(let b)): return a == b
        case (.simple(let a), .simple(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.null, .null): return true
        case (.undefined, .undefined): return true
        // Bit patterns rather than IEEE equality: see the note above.
        case (.half(let a), .half(let b)): return a == b // already a bit pattern
        case (.float(let a), .float(let b)): return a.bitPattern == b.bitPattern
        case (.double(let a), .double(let b)): return a.bitPattern == b.bitPattern
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
                    // identity — and therefore the float bit-pattern rule —
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
    /// above have matching cases here, including Swift's canonical String
    /// equality and the floats' bit-pattern identity.
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
            hasher.combine(value)
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
        // Bit patterns, to stay consistent with `==`. The standard library
        // would do the same except for normalising -0.0 to +0.0, which `==` now
        // treats as a different value.
        case .half(let bits):
            hasher.combine(11 as UInt8)
            hasher.combine(bits)
        case .float(let value):
            hasher.combine(12 as UInt8)
            hasher.combine(value.bitPattern)
        case .double(let value):
            hasher.combine(13 as UInt8)
            hasher.combine(value.bitPattern)
        case .array, .map, .tagged:
            break // handled by deepHash()
        }
    }
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
