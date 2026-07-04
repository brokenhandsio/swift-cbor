extension CBOR {
    /// Encode this data item to its CBOR byte representation.
    ///
    /// Encoding never fails: every `CBOR` value has a byte representation. When
    /// `options.deterministic` is set (the default), integers use their shortest
    /// form and map keys are emitted in RFC 8949 §4.2 canonical order.
    ///
    /// - Parameter options: Encoding options.
    /// - Returns: The encoded bytes.
    public func encode(options: CBOROptions = .default) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(16)
        appendEncoding(to: &out, options: options)
        return out
    }

    /// Append this item's encoding to an existing buffer.
    func appendEncoding(to out: inout [UInt8], options: CBOROptions) {
        switch self {
        case .unsignedInt(let value):
            appendTypedArgument(major: 0, value, to: &out)

        case .negativeInt(let value):
            appendTypedArgument(major: 1, value, to: &out)

        case .byteString(let bytes):
            appendTypedArgument(major: 2, UInt64(bytes.count), to: &out)
            out.append(contentsOf: bytes)

        case .textString(let string):
            let utf8 = Array(string.utf8)
            appendTypedArgument(major: 3, UInt64(utf8.count), to: &out)
            out.append(contentsOf: utf8)

        case .array(let elements):
            appendTypedArgument(major: 4, UInt64(elements.count), to: &out)
            for element in elements {
                element.appendEncoding(to: &out, options: options)
            }

        case .map(let entries):
            appendTypedArgument(major: 5, UInt64(entries.count), to: &out)
            appendMapBody(entries, to: &out, options: options)

        case .tagged(let tag, let item):
            appendTypedArgument(major: 6, tag.rawValue, to: &out)
            item.appendEncoding(to: &out, options: options)

        case .simple(let value):
            // Major 7: values < 24 are single-byte, 24...255 use the 0xf8 prefix,
            // which is exactly the head encoding for the argument.
            appendTypedArgument(major: 7, UInt64(value), to: &out)

        case .bool(let value):
            out.append(value ? 0xf5 : 0xf4)

        case .null:
            out.append(0xf6)

        case .undefined:
            out.append(0xf7)

        case .half(let value):
            out.append(0xf9)
            appendBigEndian(value.bitPattern, to: &out)

        case .float(let value):
            out.append(0xfa)
            appendBigEndian(value.bitPattern, to: &out)

        case .double(let value):
            out.append(0xfb)
            appendBigEndian(value.bitPattern, to: &out)
        }
    }

    private func appendMapBody(_ entries: [CBOR: CBOR], to out: inout [UInt8], options: CBOROptions) {
        guard options.deterministic else {
            for (key, value) in entries {
                key.appendEncoding(to: &out, options: options)
                value.appendEncoding(to: &out, options: options)
            }
            return
        }

        // RFC 8949 §4.2.1: emit entries sorted by the bytewise lexicographic order
        // of their encoded keys. Rather than allocating a separate buffer per key,
        // encode every key into one shared scratch buffer, remember each key's byte
        // range, and sort by comparing ranges within that buffer.
        var keyBytes: [UInt8] = []
        var sortedEntries: [(start: Int, end: Int, value: CBOR)] = []
        sortedEntries.reserveCapacity(entries.count)
        for (key, value) in entries {
            let start = keyBytes.count
            key.appendEncoding(to: &keyBytes, options: options)
            sortedEntries.append((start, keyBytes.count, value))
        }
        sortedEntries.sort { lhs, rhs in
            keyRangeIsOrderedBefore(keyBytes, lhs.start, lhs.end, rhs.start, rhs.end)
        }
        for entry in sortedEntries {
            out.append(contentsOf: keyBytes[entry.start..<entry.end])
            entry.value.appendEncoding(to: &out, options: options)
        }
    }
}

/// Bytewise lexicographic ordering of two ranges within the same buffer, where a
/// shorter range that is a prefix of the other sorts first (RFC 8949 §4.2.1).
private func keyRangeIsOrderedBefore(
    _ buffer: [UInt8],
    _ aStart: Int, _ aEnd: Int,
    _ bStart: Int, _ bEnd: Int
) -> Bool {
    var a = aStart
    var b = bStart
    while a < aEnd, b < bEnd {
        if buffer[a] != buffer[b] { return buffer[a] < buffer[b] }
        a += 1
        b += 1
    }
    return (aEnd - aStart) < (bEnd - bStart)
}

// MARK: - Head / argument encoding

/// Append a major-type head with its argument, using the shortest form.
private func appendTypedArgument(major: UInt8, _ value: UInt64, to out: inout [UInt8]) {
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
