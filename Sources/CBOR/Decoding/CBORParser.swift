/// A non-recursive CBOR parser that reads through a borrowed `Span<UInt8>`.
///
/// Nested containers are tracked on an explicit heap-allocated stack rather than
/// via native recursion, so the parser's native stack usage is O(1) regardless of
/// how deeply the input nests. `CBOROptions.maximumDepth` therefore bounds only the
/// (cheap) heap stack and cannot be turned into a stack overflow — decoding hostile,
/// deeply nested input fails with ``CBORError/maxDepthExceeded(_:)`` instead of
/// trapping.
///
/// All reads go through `Span`'s bounds-checked subscript, so the parser is fully
/// memory-safe (no `unsafe`, no pointer arithmetic).
enum CBORParser {
    /// An in-progress container awaiting its remaining children.
    private struct Frame {
        enum Kind { case array, indefiniteArray, map, indefiniteMap, tag }
        var kind: Kind
        var remaining: Int = 0            // definite array/map: children/pairs still expected
        var items: [CBOR] = []
        var pairs: [CBOR: CBOR] = [:]
        var pendingKey: CBOR? = nil       // map: a key awaiting its value
        var tag: CBORTag = CBORTag(0)

        var isIndefinite: Bool { kind == .indefiniteArray || kind == .indefiniteMap }

        /// Incorporate a completed child `value`. Returns the finished container when
        /// this frame is now complete, otherwise `nil`.
        @inline(__always)
        mutating func accept(_ value: CBOR, rejectDuplicates: Bool) throws -> CBOR? {
            switch kind {
            case .array:
                items.append(value)
                remaining -= 1
                return remaining == 0 ? .array(items) : nil
            case .indefiniteArray:
                items.append(value)
                return nil
            case .map:
                if let key = pendingKey {
                    if rejectDuplicates, pairs[key] != nil { throw CBORError.duplicateMapKey }
                    pairs[key] = value
                    pendingKey = nil
                    remaining -= 1
                    return remaining == 0 ? .map(pairs) : nil
                }
                pendingKey = value
                return nil
            case .indefiniteMap:
                if let key = pendingKey {
                    if rejectDuplicates, pairs[key] != nil { throw CBORError.duplicateMapKey }
                    pairs[key] = value
                    pendingKey = nil
                } else {
                    pendingKey = value
                }
                return nil
            case .tag:
                return .tagged(tag, value) // a tag holds exactly one item
            }
        }
    }

    /// Parse a single data item starting at `offset`, advancing it past the item.
    static func parseItem(
        _ span: Span<UInt8>,
        _ offset: inout Int,
        options: CBOROptions
    ) throws -> CBOR {
        let maxDepth = options.maximumDepth
        let rejectDuplicates = options.rejectDuplicateMapKeys
        var stack: [Frame] = []

        while true {
            // A `break` (0xFF) closes the innermost indefinite-length container.
            // The `span[offset] == 0xff` test is checked first so the common path
            // (any non-break byte) never touches the frame — reading `stack.last`
            // would otherwise copy the whole frame (and retain its arrays) here on
            // every single iteration.
            if offset < span.count, span[offset] == 0xff,
               !stack.isEmpty, stack[stack.count - 1].isIndefinite {
                offset += 1
                let frame = stack.removeLast()
                let completed: CBOR
                if frame.kind == .indefiniteArray {
                    completed = .array(frame.items)
                } else {
                    if frame.pendingKey != nil { throw CBORError.invalidIndefiniteLength }
                    completed = .map(frame.pairs)
                }
                if let result = try attach(completed, to: &stack, rejectDuplicates: rejectDuplicates) {
                    return result
                }
                continue
            }

            // The item about to be read sits at depth `stack.count`.
            if stack.count > maxDepth {
                throw CBORError.maxDepthExceeded(maxDepth)
            }

            let initialByte = try readByte(span, &offset)
            let major = initialByte >> 5
            let additional = initialByte & 0x1f

            // Containers push a frame and continue; scalars fall through to `attach`.
            var scalar: CBOR? = nil
            switch major {
            case 0:
                scalar = .unsignedInt(try readArgument(additional, span, &offset))

            case 1:
                scalar = .negativeInt(try readArgument(additional, span, &offset))

            case 2:
                if additional == 31 {
                    scalar = try readIndefiniteByteString(span, &offset)
                } else {
                    let length = try readArgument(additional, span, &offset)
                    scalar = .byteString(try readBytes(length, span, &offset))
                }

            case 3:
                if additional == 31 {
                    scalar = try readIndefiniteTextString(span, &offset)
                } else {
                    let length = try readArgument(additional, span, &offset)
                    scalar = .textString(try readTextString(length, span, &offset))
                }

            case 4:
                if additional == 31 {
                    stack.append(Frame(kind: .indefiniteArray))
                    continue
                }
                let count = try readCount(additional, span, &offset)
                if count == 0 {
                    scalar = .array([])
                } else {
                    var frame = Frame(kind: .array)
                    frame.remaining = count
                    frame.items.reserveCapacity(min(count, 1024))
                    stack.append(frame)
                    continue
                }

            case 5:
                if additional == 31 {
                    stack.append(Frame(kind: .indefiniteMap))
                    continue
                }
                let count = try readCount(additional, span, &offset)
                if count == 0 {
                    scalar = .map([:])
                } else {
                    var frame = Frame(kind: .map)
                    frame.remaining = count
                    frame.pairs.reserveCapacity(min(count, 1024))
                    stack.append(frame)
                    continue
                }

            case 6:
                var frame = Frame(kind: .tag)
                frame.tag = CBORTag(try readArgument(additional, span, &offset))
                stack.append(frame)
                continue

            default: // 7
                scalar = try parseSimpleOrFloat(additional, span, &offset)
            }

            if let scalar, let result = try attach(scalar, to: &stack, rejectDuplicates: rejectDuplicates) {
                return result
            }
        }
    }

    /// Attach a completed value to the innermost open container, cascading upward as
    /// containers fill. Returns the top-level value once the stack is empty.
    @inline(__always)
    private static func attach(
        _ value: CBOR,
        to stack: inout [Frame],
        rejectDuplicates: Bool
    ) throws -> CBOR? {
        var current = value
        while true {
            if stack.isEmpty { return current }
            if let completed = try stack[stack.count - 1].accept(current, rejectDuplicates: rejectDuplicates) {
                stack.removeLast()
                current = completed
            } else {
                return nil
            }
        }
    }

    // MARK: Primitive reads

    @inline(__always)
    private static func readByte(_ span: Span<UInt8>, _ offset: inout Int) throws -> UInt8 {
        guard offset < span.count else { throw CBORError.unexpectedEnd }
        let byte = span[offset]
        offset += 1
        return byte
    }

    /// Read the argument that follows a head byte's additional-information value.
    @inline(__always)
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

    /// Read a definite length/count as an `Int`, rejecting values that don't fit.
    private static func readCount(
        _ additional: UInt8,
        _ span: Span<UInt8>,
        _ offset: inout Int
    ) throws -> Int {
        guard let count = Int(exactly: try readArgument(additional, span, &offset)) else {
            throw CBORError.unexpectedEnd
        }
        return count
    }

    @inline(__always)
    private static func readUInt16(_ span: Span<UInt8>, _ offset: inout Int) throws -> UInt16 {
        let high = try readByte(span, &offset)
        let low = try readByte(span, &offset)
        return UInt16(high) << 8 | UInt16(low)
    }

    @inline(__always)
    private static func readUInt32(_ span: Span<UInt8>, _ offset: inout Int) throws -> UInt32 {
        var result: UInt32 = 0
        for _ in 0..<4 {
            result = result << 8 | UInt32(try readByte(span, &offset))
        }
        return result
    }

    @inline(__always)
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

    // MARK: Indefinite-length strings
    //
    // Indefinite byte/text strings only contain definite-length string chunks, so
    // they are read in a flat loop — no container frame or recursion needed.

    private static func readIndefiniteByteString(
        _ span: Span<UInt8>,
        _ offset: inout Int
    ) throws -> CBOR {
        var bytes: [UInt8] = []
        while true {
            let initialByte = try readByte(span, &offset)
            if initialByte == 0xff { break }
            guard initialByte >> 5 == 2, initialByte & 0x1f != 31 else {
                throw CBORError.invalidIndefiniteLength
            }
            let length = try readArgument(initialByte & 0x1f, span, &offset)
            bytes.append(contentsOf: try readBytes(length, span, &offset))
        }
        return .byteString(bytes)
    }

    private static func readIndefiniteTextString(
        _ span: Span<UInt8>,
        _ offset: inout Int
    ) throws -> CBOR {
        var bytes: [UInt8] = []
        while true {
            let initialByte = try readByte(span, &offset)
            if initialByte == 0xff { break }
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
