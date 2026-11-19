extension CBOR {
    /// Encode this data item to its CBOR byte representation.
    ///
    /// Encoding never fails: every `CBOR` value has a byte representation.
    ///
    /// The output is deterministic: the same value always encodes to the same
    /// bytes. Integers, lengths and tags use their shortest form, lengths are always
    /// definite, and map keys are sorted into bytewise lexicographic order of their
    /// encodings (RFC 8949 §4.2.1). Floats keep the width of their case
    /// (``CBOR/half(bitPattern:)``, ``CBOR/float(_:)`` or ``CBOR/double(_:)``) rather
    /// than being narrowed, so a value that §4.2.1 would shorten, such as
    /// `.double(1.5)`, is written at its declared width.
    ///
    /// Nested containers are walked with an explicit work stack rather than native
    /// recursion, so encoding a deeply nested value uses O(1) native stack and
    /// cannot overflow it.
    ///
    /// - Returns: The encoded bytes.
    public func encode() -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(16)
        appendEncoding(to: &out)
        return out
    }

    /// Append this item's encoding to an existing buffer, iteratively.
    func appendEncoding(to out: inout [UInt8]) {
        // The work stack only grows when a nested container is encountered; a flat
        // value (or a scalar) never allocates it — runs of scalars are written inline.
        var stack: [EncodeTask] = []
        var task = EncodeTask.value(self)
        while true {
            switch task {
            case .value(let cbor):
                emit(cbor, to: &out, stack: &stack)
            case .arrayElements(let elements, let index):
                emitArray(elements, from: index, to: &out, stack: &stack)
            case .mapEntries(let keyBytes, let ranges, let index):
                emitMap(keyBytes, ranges, from: index, to: &out, stack: &stack)
            }
            guard let next = stack.popLast() else { break }
            task = next
        }
    }

    /// Whether this value has no nested items (can be written without the work stack).
    var isScalar: Bool {
        switch self {
        case .array, .map, .tagged: return false
        default: return true
        }
    }

    /// Append the bytes of a scalar (non-container) value.
    func appendScalarBytes(to out: inout [UInt8]) {
        switch self {
        case .unsignedInt(let value):
            appendTypedArgument(major: 0, value, to: &out)
        case .negativeInt(let value):
            appendTypedArgument(major: 1, value, to: &out)
        case .byteString(let bytes):
            appendTypedArgument(major: 2, UInt64(bytes.count), to: &out)
            out.append(contentsOf: bytes)
        case .textString(let string):
            // Straight from the string's storage: `utf8.count` is O(1) for a
            // native string, and appending the view copies its contiguous bytes
            // in one go, with no intermediate array.
            appendTypedArgument(major: 3, UInt64(string.utf8.count), to: &out)
            out.append(contentsOf: string.utf8)
        case .simple(let value):
            // Major 7 with the value as its argument: 0...19 fit in the head byte and
            // 32...255 take the 0xf8 prefix. `CBORSimpleValue` rules out 20...31, the
            // values that would collide with `.bool`/`.null`/`.undefined` or need the
            // ill-formed two-byte form.
            appendTypedArgument(major: 7, UInt64(value.rawValue), to: &out)
        case .bool(let value):
            out.append(value ? 0xf5 : 0xf4)
        case .null:
            out.append(0xf6)
        case .undefined:
            out.append(0xf7)
        case .half(let bits):
            out.append(0xf9)
            appendBigEndian(bits, to: &out)
        case .float(let value):
            out.append(0xfa)
            appendBigEndian(value.bitPattern, to: &out)
        case .double(let value):
            out.append(0xfb)
            appendBigEndian(value.bitPattern, to: &out)
        case .array, .map, .tagged:
            break // containers are handled iteratively and never reach here
        }
    }
}

// MARK: - Iterative walk

/// A pending unit of encoding work.
private enum EncodeTask {
    case value(CBOR)
    /// Resume writing an array's elements from the given index.
    case arrayElements([CBOR], Int)
    /// Resume writing a map's (already key-sorted) entries from the given index.
    case mapEntries([UInt8], [(start: Int, end: Int, value: CBOR)], Int)
}

private func emit(_ cbor: CBOR, to out: inout [UInt8], stack: inout [EncodeTask]) {
    switch cbor {
    case .array(let elements):
        appendTypedArgument(major: 4, UInt64(elements.count), to: &out)
        emitArray(elements, from: 0, to: &out, stack: &stack)
    case .map(let entries):
        appendTypedArgument(major: 5, UInt64(entries.count), to: &out)
        emitMapValue(entries, to: &out, stack: &stack)
    case .tagged:
        // Write the tag heads in a loop, so nested tags need no stack, then the
        // item. A container item is emitted here directly, which recurses at most
        // once: it is not a tag.
        var inner = cbor
        while case .tagged(let tag, let item) = inner {
            appendTypedArgument(major: 6, tag.rawValue, to: &out)
            inner = item
        }
        if inner.isScalar {
            inner.appendScalarBytes(to: &out)
        } else {
            emit(inner, to: &out, stack: &stack)
        }
    default:
        cbor.appendScalarBytes(to: &out)
    }
}

/// Write `value` and return `true` if it contains no container: a scalar, or tags
/// around one. Write nothing and return `false` otherwise, so the caller can defer
/// it to the work stack.
///
/// Tags around a scalar are common (a date, a bignum, an embedded item), and
/// writing them inline keeps them from allocating the work stack.
@inline(__always)
private func appendIfLeaf(_ value: CBOR, to out: inout [UInt8]) -> Bool {
    if value.isScalar {
        value.appendScalarBytes(to: &out)
        return true
    }
    guard case .tagged = value else { return false }
    var inner = value
    while case .tagged(_, let item) = inner { inner = item }
    guard inner.isScalar else { return false }
    var current = value
    while case .tagged(let tag, let item) = current {
        appendTypedArgument(major: 6, tag.rawValue, to: &out)
        current = item
    }
    current.appendScalarBytes(to: &out)
    return true
}

/// Write array elements inline until a nested container is reached, at which point
/// the remainder is deferred to the work stack.
private func emitArray(
    _ elements: [CBOR], from start: Int,
    to out: inout [UInt8], stack: inout [EncodeTask]
) {
    var index = start
    while index < elements.count {
        let element = elements[index]
        if appendIfLeaf(element, to: &out) {
            index += 1
        } else {
            stack.append(.arrayElements(elements, index + 1))
            stack.append(.value(element))
            return
        }
    }
}

/// Encode a map's keys into one scratch buffer, sort them, then write the entries.
private func emitMapValue(
    _ entries: [CBOR: CBOR],
    to out: inout [UInt8], stack: inout [EncodeTask]
) {
    guard !entries.isEmpty else { return }
    var keyBytes: [UInt8] = []
    var ranges: [(start: Int, end: Int, value: CBOR)] = []
    ranges.reserveCapacity(entries.count)
    for (key, value) in entries {
        let start = keyBytes.count
        if !appendIfLeaf(key, to: &keyBytes) {
            key.appendEncoding(to: &keyBytes)
        }
        ranges.append((start, keyBytes.count, value))
    }
    // RFC 8949 §4.2.1: bytewise lexicographic order of the encoded keys. `entries`
    // is a `Dictionary`, so without sorting the order would change between runs.
    ranges.sort { keyRangeIsOrderedBefore(keyBytes, $0.start, $0.end, $1.start, $1.end) }
    emitMap(keyBytes, ranges, from: 0, to: &out, stack: &stack)
}

/// Write map entries inline until a nested value is reached, deferring the rest.
private func emitMap(
    _ keyBytes: [UInt8], _ ranges: [(start: Int, end: Int, value: CBOR)], from start: Int,
    to out: inout [UInt8], stack: inout [EncodeTask]
) {
    var index = start
    while index < ranges.count {
        let range = ranges[index]
        out.append(contentsOf: keyBytes[range.start..<range.end])
        if appendIfLeaf(range.value, to: &out) {
            index += 1
        } else {
            stack.append(.mapEntries(keyBytes, ranges, index + 1))
            stack.append(.value(range.value))
            return
        }
    }
}

// MARK: - Head / argument encoding

/// Append a major-type head with its argument, using the shortest form.
func appendTypedArgument(major: UInt8, _ value: UInt64, to out: inout [UInt8]) {
    let head = major << 5
    switch value {
    case 0..<24:
        out.append(head | UInt8(value))
    case 24..<0x100:
        out.append(head | 24)
        out.append(UInt8(value))
    case 0x100..<0x1_0000:
        out.append(head | 25)
        appendBigEndian(UInt16(value), to: &out)
    case 0x1_0000..<0x1_0000_0000:
        out.append(head | 26)
        appendBigEndian(UInt32(value), to: &out)
    default:
        out.append(head | 27)
        appendBigEndian(value, to: &out)
    }
}

private func appendBigEndian(_ value: UInt16, to out: inout [UInt8]) {
    out.append(UInt8(truncatingIfNeeded: value >> 8))
    out.append(UInt8(truncatingIfNeeded: value))
}

private func appendBigEndian(_ value: UInt32, to out: inout [UInt8]) {
    out.append(UInt8(truncatingIfNeeded: value >> 24))
    out.append(UInt8(truncatingIfNeeded: value >> 16))
    out.append(UInt8(truncatingIfNeeded: value >> 8))
    out.append(UInt8(truncatingIfNeeded: value))
}

private func appendBigEndian(_ value: UInt64, to out: inout [UInt8]) {
    var shift: UInt64 = 56
    while true {
        out.append(UInt8(truncatingIfNeeded: value >> shift))
        if shift == 0 { break }
        shift -= 8
    }
}

/// Bytewise lexicographic ordering of two ranges within the same buffer, where a
/// shorter range that is a prefix of the other sorts first (RFC 8949 §4.2.1).
func keyRangeIsOrderedBefore(
    _ buffer: [UInt8],
    _ aStart: Int, _ aEnd: Int,
    _ bStart: Int, _ bEnd: Int
) -> Bool {
    compareKeyRanges(buffer, aStart, aEnd, bStart, bEnd) < 0
}

/// The same ordering as ``keyRangeIsOrderedBefore(_:_:_:_:_:)`` as a three-way
/// comparison: negative, zero or positive as range `a` sorts before, equal to, or
/// after range `b`.
@inline(__always)
func compareKeyRanges(
    _ buffer: [UInt8],
    _ aStart: Int, _ aEnd: Int,
    _ bStart: Int, _ bEnd: Int
) -> Int {
    var a = aStart
    var b = bStart
    while a < aEnd, b < bEnd {
        if buffer[a] != buffer[b] { return buffer[a] < buffer[b] ? -1 : 1 }
        a += 1
        b += 1
    }
    return (aEnd - aStart) - (bEnd - bStart)
}
