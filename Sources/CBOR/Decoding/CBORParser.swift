/// A recursive-descent CBOR parser that reads through a borrowed `Span<UInt8>`.
///
/// All reads go through `Span`'s bounds-checked subscript, so the parser is fully
/// memory-safe (no `unsafe`, no pointer arithmetic). The span is passed by value
/// (a `Span` is a cheap, non-escapable view) and a plain `inout Int` cursor tracks
/// the read position.
enum CBORParser {
    /// Parse a single data item starting at `offset`, advancing it past the item.
    static func parseItem(
        _ span: Span<UInt8>,
        _ offset: inout Int,
        depth: Int,
        options: CBOROptions
    ) throws -> CBOR {
        if depth > options.maximumDepth {
            throw CBORError.maxDepthExceeded(options.maximumDepth)
        }

        let initialByte = try readByte(span, &offset)
        let major = initialByte >> 5
        let additional = initialByte & 0x1f

        switch major {
        case 0:
            return .unsignedInt(try readArgument(additional, span, &offset))

        case 1:
            return .negativeInt(try readArgument(additional, span, &offset))

        case 2:
            if additional == 31 {
                return try parseIndefiniteByteString(span, &offset)
            }
            let length = try readArgument(additional, span, &offset)
            return .byteString(try readBytes(length, span, &offset))

        case 3:
            if additional == 31 {
                return try parseIndefiniteTextString(span, &offset)
            }
            let length = try readArgument(additional, span, &offset)
            return .textString(try readTextString(length, span, &offset))

        case 4:
            if additional == 31 {
                return try parseIndefiniteArray(span, &offset, depth: depth, options: options)
            }
            let count = try readArgument(additional, span, &offset)
            return try parseArray(count, span, &offset, depth: depth, options: options)

        case 5:
            if additional == 31 {
                return try parseIndefiniteMap(span, &offset, depth: depth, options: options)
            }
            let count = try readArgument(additional, span, &offset)
            return try parseMap(count, span, &offset, depth: depth, options: options)

        case 6:
            let tag = try readArgument(additional, span, &offset)
            let item = try parseItem(span, &offset, depth: depth + 1, options: options)
            return .tagged(CBORTag(tag), item)

        default: // 7
            return try parseSimpleOrFloat(additional, span, &offset)
        }
    }

    // MARK: Primitive reads

    private static func readByte(_ span: Span<UInt8>, _ offset: inout Int) throws -> UInt8 {
        guard offset < span.count else { throw CBORError.unexpectedEnd }
        let byte = span[offset]
        offset += 1
        return byte
    }

    /// Read the argument that follows a head byte's additional-information value.
    private static func readArgument(
        _ additional: UInt8,
        _ span: Span<UInt8>,
        _ offset: inout Int
    ) throws -> UInt64 {
        switch additional {
        case 0..<24:
            return UInt64(additional)
        case 24:
            return UInt64(try readByte(span, &offset))
        case 25:
            return UInt64(try readUInt16(span, &offset))
        case 26:
            return UInt64(try readUInt32(span, &offset))
        case 27:
            return try readUInt64(span, &offset)
        case 31:
            throw CBORError.invalidIndefiniteLength
        default: // 28, 29, 30
            throw CBORError.reservedAdditionalInfo(additional)
        }
    }

    private static func readUInt16(_ span: Span<UInt8>, _ offset: inout Int) throws -> UInt16 {
        let high = try readByte(span, &offset)
        let low = try readByte(span, &offset)
        return UInt16(high) << 8 | UInt16(low)
    }

    private static func readUInt32(_ span: Span<UInt8>, _ offset: inout Int) throws -> UInt32 {
        var result: UInt32 = 0
        for _ in 0..<4 {
            result = result << 8 | UInt32(try readByte(span, &offset))
        }
        return result
    }

    private static func readUInt64(_ span: Span<UInt8>, _ offset: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        for _ in 0..<8 {
            result = result << 8 | UInt64(try readByte(span, &offset))
        }
        return result
    }

    /// Read `length` raw bytes, copying them into an array.
    private static func readBytes(
        _ length: UInt64,
        _ span: Span<UInt8>,
        _ offset: inout Int
    ) throws -> [UInt8] {
        guard let count = Int(exactly: length),
              count <= span.count - offset else {
            throw CBORError.unexpectedEnd
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(count)
        let end = offset + count
        var index = offset
        while index < end {
            bytes.append(span[index])
            index += 1
        }
        offset = end
        return bytes
    }

    private static func readTextString(
        _ length: UInt64,
        _ span: Span<UInt8>,
        _ offset: inout Int
    ) throws -> String {
        let raw = try readBytes(length, span, &offset)
        guard let string = String(validating: raw, as: UTF8.self) else {
            throw CBORError.invalidUTF8
        }
        return string
    }

    // MARK: Definite-length containers

    private static func parseArray(
        _ count: UInt64,
        _ span: Span<UInt8>,
        _ offset: inout Int,
        depth: Int,
        options: CBOROptions
    ) throws -> CBOR {
        guard let capacity = Int(exactly: count) else { throw CBORError.unexpectedEnd }
        var elements: [CBOR] = []
        elements.reserveCapacity(Swift.min(capacity, 1024))
        for _ in 0..<capacity {
            elements.append(try parseItem(span, &offset, depth: depth + 1, options: options))
        }
        return .array(elements)
    }

    private static func parseMap(
        _ count: UInt64,
        _ span: Span<UInt8>,
        _ offset: inout Int,
        depth: Int,
        options: CBOROptions
    ) throws -> CBOR {
        guard let capacity = Int(exactly: count) else { throw CBORError.unexpectedEnd }
        var entries: [CBOR: CBOR] = .init(minimumCapacity: Swift.min(capacity, 1024))
        for _ in 0..<capacity {
            let key = try parseItem(span, &offset, depth: depth + 1, options: options)
            let value = try parseItem(span, &offset, depth: depth + 1, options: options)
            if options.rejectDuplicateMapKeys, entries[key] != nil {
                throw CBORError.duplicateMapKey
            }
            entries[key] = value
        }
        return .map(entries)
    }

    // MARK: Indefinite-length items

    private static func parseIndefiniteByteString(
        _ span: Span<UInt8>,
        _ offset: inout Int
    ) throws -> CBOR {
        var bytes: [UInt8] = []
        while true {
            let initialByte = try readByte(span, &offset)
            if initialByte == 0xff { break }
            // Each chunk must be a definite-length byte string.
            guard initialByte >> 5 == 2, initialByte & 0x1f != 31 else {
                throw CBORError.invalidIndefiniteLength
            }
            let length = try readArgument(initialByte & 0x1f, span, &offset)
            bytes.append(contentsOf: try readBytes(length, span, &offset))
        }
        return .byteString(bytes)
    }

    private static func parseIndefiniteTextString(
        _ span: Span<UInt8>,
        _ offset: inout Int
    ) throws -> CBOR {
        var bytes: [UInt8] = []
        while true {
            let initialByte = try readByte(span, &offset)
            if initialByte == 0xff { break }
            // Each chunk must be a definite-length text string.
            guard initialByte >> 5 == 3, initialByte & 0x1f != 31 else {
                throw CBORError.invalidIndefiniteLength
            }
            let length = try readArgument(initialByte & 0x1f, span, &offset)
            bytes.append(contentsOf: try readBytes(length, span, &offset))
        }
        guard let string = String(validating: bytes, as: UTF8.self) else {
            throw CBORError.invalidUTF8
        }
        return .textString(string)
    }

    private static func parseIndefiniteArray(
        _ span: Span<UInt8>,
        _ offset: inout Int,
        depth: Int,
        options: CBOROptions
    ) throws -> CBOR {
        var elements: [CBOR] = []
        while true {
            guard offset < span.count else { throw CBORError.unexpectedEnd }
            if span[offset] == 0xff {
                offset += 1
                break
            }
            elements.append(try parseItem(span, &offset, depth: depth + 1, options: options))
        }
        return .array(elements)
    }

    private static func parseIndefiniteMap(
        _ span: Span<UInt8>,
        _ offset: inout Int,
        depth: Int,
        options: CBOROptions
    ) throws -> CBOR {
        var entries: [CBOR: CBOR] = [:]
        while true {
            guard offset < span.count else { throw CBORError.unexpectedEnd }
            if span[offset] == 0xff {
                offset += 1
                break
            }
            let key = try parseItem(span, &offset, depth: depth + 1, options: options)
            let value = try parseItem(span, &offset, depth: depth + 1, options: options)
            if options.rejectDuplicateMapKeys, entries[key] != nil {
                throw CBORError.duplicateMapKey
            }
            entries[key] = value
        }
        return .map(entries)
    }

    // MARK: Major type 7

    private static func parseSimpleOrFloat(
        _ additional: UInt8,
        _ span: Span<UInt8>,
        _ offset: inout Int
    ) throws -> CBOR {
        switch additional {
        case 0..<20:
            return .simple(additional)
        case 20:
            return .bool(false)
        case 21:
            return .bool(true)
        case 22:
            return .null
        case 23:
            return .undefined
        case 24:
            let value = try readByte(span, &offset)
            // Simple values 0...31 must use the single-byte form, not 0xf8.
            guard value >= 32 else { throw CBORError.reservedAdditionalInfo(24) }
            return .simple(value)
        case 25:
            return .half(Float16(bitPattern: try readUInt16(span, &offset)))
        case 26:
            return .float(Float(bitPattern: try readUInt32(span, &offset)))
        case 27:
            return .double(Double(bitPattern: try readUInt64(span, &offset)))
        case 31:
            // A break stop code where a data item was expected.
            throw CBORError.unexpectedBreak
        default: // 28, 29, 30
            throw CBORError.reservedAdditionalInfo(additional)
        }
    }
}
