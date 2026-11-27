/// A non-recursive CBOR parser that reads through a borrowed `Span<UInt8>`.
///
/// Nested containers are tracked on an explicit heap-allocated stack rather than
/// via native recursion, so the parser's native stack usage is O(1) regardless of
/// how deeply the input nests. Decoding hostile, deeply nested input fails with
/// ``CBORError/maxDepthExceeded(limit:offset:)`` instead of trapping.
///
/// Depth is capped at ``CBORDecodingOptions/maximumSupportedDepth`` regardless of what
/// ``CBORDecodingOptions/maximumDepth`` requests. Parsing itself would happily go deeper —
/// its stack is on the heap — but the resulting value is a recursive tree that the
/// Swift runtime tears down recursively when it is released, and that recursion is
/// not something this library can intercept. Refusing to build such a value is the
/// only way to keep the promise that decoding untrusted bytes cannot crash.
///
/// All reads go through `Span`'s bounds-checked subscript, so the parser is fully
/// memory-safe (no `unsafe`, no pointer arithmetic).
enum CBORParser {
    /// An in-progress container awaiting its remaining children.
    private struct Frame {
        enum Kind { case array, indefiniteArray, map, indefiniteMap, tag }
        var kind: Kind
        var start: Int                    // offset of the container's head, for errors
        var remaining: Int = 0            // definite array/map: children/pairs still expected
        var items: [CBOR] = []
        var pairs: [CBOR: CBOR] = [:]
        var pendingKey: CBOR? = nil       // map: a key awaiting its value
        var pendingKeyStart: Int = 0      // map: offset of `pendingKey`, for errors
        var tag: CBORTag = CBORTag(0)

        var isIndefinite: Bool { kind == .indefiniteArray || kind == .indefiniteMap }

        /// Incorporate a completed child `value`, whose head is at `valueStart`.
        /// Returns the finished container when this frame is now complete, otherwise
        /// `nil`.
        @inline(__always)
        mutating func accept(_ value: CBOR, at valueStart: Int, rejectDuplicates: Bool) throws -> CBOR? {
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
                    // `updateValue` both inserts and reports a previous entry, so
                    // rejecting duplicates costs no extra hash lookup.
                    if pairs.updateValue(value, forKey: key) != nil, rejectDuplicates {
                        throw CBORError.duplicateMapKey(offset: pendingKeyStart)
                    }
                    pendingKey = nil
                    remaining -= 1
                    return remaining == 0 ? .map(pairs) : nil
                }
                pendingKey = value
                pendingKeyStart = valueStart
                return nil
            case .indefiniteMap:
                if let key = pendingKey {
                    if pairs.updateValue(value, forKey: key) != nil, rejectDuplicates {
                        throw CBORError.duplicateMapKey(offset: pendingKeyStart)
                    }
                    pendingKey = nil
                } else {
                    pendingKey = value
                    pendingKeyStart = valueStart
                }
                return nil
            case .tag:
                return .tagged(tag, value) // a tag holds exactly one item
            }
        }
    }

    /// Parse a single data item starting at `offset`, advancing it past the item.
    ///
    /// `source`, when given, is the array slice that `span` views. Byte strings are
    /// then copied out of it, which is a block copy; a bare `Span` can only be
    /// copied from element by element.
    static func parseItem(
        _ span: Span<UInt8>,
        _ offset: inout Int,
        options: CBORDecodingOptions,
        source: ArraySlice<UInt8>? = nil
    ) throws -> CBOR {
        // Clamped, not trusted: a value nested deeper than this decodes fine and
        // then overflows the stack when the runtime releases it. See
        // `CBORDecodingOptions.maximumSupportedDepth`.
        let maxDepth = min(options.maximumDepth, CBORDecodingOptions.maximumSupportedDepth)
        let rejectDuplicates = options.rejectDuplicateMapKeys
        var stack: [Frame] = []
        // A count is untrusted until its children arrive. A single budget keeps
        // eager reservations across all open frames proportional to input size.
        var reservationBudget = span.count

        while true {
            // A `break` (0xFF) closes the innermost indefinite-length container.
            // The `span[offset] == 0xff` test is checked first so the common path
            // (any non-break byte) never touches the frame — reading `stack.last`
            // would otherwise copy the whole frame (and retain its arrays) here on
            // every single iteration.
            if offset < span.count, span[offset] == 0xff,
               !stack.isEmpty, stack[stack.count - 1].isIndefinite {
                let breakOffset = offset
                offset += 1
                let frame = stack.removeLast()
                let completed: CBOR
                if frame.kind == .indefiniteArray {
                    completed = .array(frame.items)
                } else {
                    if frame.pendingKey != nil {
                        throw CBORError.invalidIndefiniteLength(offset: breakOffset)
                    }
                    completed = .map(frame.pairs)
                }
                if let result = try attach(completed, at: frame.start, to: &stack, rejectDuplicates: rejectDuplicates) {
                    return result
                }
                continue
            }

            // The item about to be read sits at depth `stack.count`.
            if stack.count > maxDepth {
                throw CBORError.maxDepthExceeded(limit: maxDepth, offset: offset)
            }

            // Where this item's head is: every error raised while reading it says so.
            let start = offset
            let initialByte = try readByte(span, &offset, item: start)
            let major = initialByte >> 5
            let additional = initialByte & 0x1f

            // Containers push a frame and continue; scalars fall through to `attach`.
            var scalar: CBOR? = nil
            switch major {
            case 0:
                scalar = .unsignedInt(try readArgument(additional, span, &offset, item: start))

            case 1:
                scalar = .negativeInt(try readArgument(additional, span, &offset, item: start))

            case 2:
                if additional == 31 {
                    scalar = try readIndefiniteByteString(span, &offset, item: start, source: source)
                } else {
                    let length = try readArgument(additional, span, &offset, item: start)
                    scalar = .byteString(try readBytes(length, span, &offset, item: start, source: source))
                }

            case 3:
                if additional == 31 {
                    scalar = try readIndefiniteTextString(span, &offset, item: start, source: source)
                } else {
                    let length = try readArgument(additional, span, &offset, item: start)
                    scalar = .textString(try readTextString(length, span, &offset, item: start, source: source))
                }

            case 4:
                if additional == 31 {
                    stack.append(Frame(kind: .indefiniteArray, start: start))
                    continue
                }
                let count = try readCount(additional, span, &offset, item: start)
                if count == 0 {
                    scalar = .array([])
                } else {
                    var frame = Frame(kind: .array, start: start)
                    frame.remaining = count
                    let capacity = min(count, min(1024, reservationBudget))
                    frame.items.reserveCapacity(capacity)
                    reservationBudget -= capacity
                    stack.append(frame)
                    continue
                }

            case 5:
                if additional == 31 {
                    stack.append(Frame(kind: .indefiniteMap, start: start))
                    continue
                }
                let count = try readCount(additional, span, &offset, item: start)
                if count == 0 {
                    scalar = .map([:])
                } else {
                    var frame = Frame(kind: .map, start: start)
                    frame.remaining = count
                    let capacity = min(count, min(1024, reservationBudget))
                    frame.pairs.reserveCapacity(capacity)
                    reservationBudget -= capacity
                    stack.append(frame)
                    continue
                }

            case 6:
                var frame = Frame(kind: .tag, start: start)
                frame.tag = CBORTag(try readArgument(additional, span, &offset, item: start))
                stack.append(frame)
                continue

            default: // 7
                scalar = try parseSimpleOrFloat(additional, span, &offset, item: start)
            }

            if let scalar, let result = try attach(scalar, at: start, to: &stack, rejectDuplicates: rejectDuplicates) {
                return result
            }
        }
    }

    /// Attach a completed value, whose head is at `start`, to the innermost open
    /// container, cascading upward as containers fill. Returns the top-level value
    /// once the stack is empty.
    @inline(__always)
    private static func attach(
        _ value: CBOR,
        at start: Int,
        to stack: inout [Frame],
        rejectDuplicates: Bool
    ) throws -> CBOR? {
        var current = value
        var currentStart = start
        while true {
            if stack.isEmpty { return current }
            if let completed = try stack[stack.count - 1].accept(
                current, at: currentStart, rejectDuplicates: rejectDuplicates
            ) {
                currentStart = stack[stack.count - 1].start
                stack.removeLast()
                current = completed
            } else {
                return nil
            }
        }
    }

    // MARK: Primitive reads
    //
    // Each read takes `item`, the offset of the head of the data item it is part of,
    // so that an error points at the item rather than at the byte that was missing.

    @inline(__always)
    private static func readByte(_ span: Span<UInt8>, _ offset: inout Int, item start: Int) throws -> UInt8 {
        guard offset < span.count else { throw CBORError.unexpectedEnd(offset: start) }
        let byte = span[offset]
        offset += 1
        return byte
    }

    /// Read the argument that follows a head byte's additional-information value.
    @inline(__always)
    private static func readArgument(
        _ additional: UInt8,
        _ span: Span<UInt8>,
        _ offset: inout Int,
        item start: Int
    ) throws -> UInt64 {
        switch additional {
        case 0..<24:
            return UInt64(additional)
        case 24:
            return UInt64(try readByte(span, &offset, item: start))
        case 25:
            return UInt64(try readUInt16(span, &offset, item: start))
        case 26:
            return UInt64(try readUInt32(span, &offset, item: start))
        case 27:
            return try readUInt64(span, &offset, item: start)
        case 31:
            throw CBORError.invalidIndefiniteLength(offset: start)
        default: // 28, 29, 30
            throw CBORError.reservedAdditionalInfo(additional, offset: start)
        }
    }

    /// Read a definite length/count as an `Int`, rejecting values that don't fit.
    private static func readCount(
        _ additional: UInt8,
        _ span: Span<UInt8>,
        _ offset: inout Int,
        item start: Int
    ) throws -> Int {
        guard let count = Int(exactly: try readArgument(additional, span, &offset, item: start)) else {
            throw CBORError.unexpectedEnd(offset: start)
        }
        return count
    }

    @inline(__always)
    private static func readUInt16(_ span: Span<UInt8>, _ offset: inout Int, item start: Int) throws -> UInt16 {
        let high = try readByte(span, &offset, item: start)
        let low = try readByte(span, &offset, item: start)
        return UInt16(high) << 8 | UInt16(low)
    }

    @inline(__always)
    private static func readUInt32(_ span: Span<UInt8>, _ offset: inout Int, item start: Int) throws -> UInt32 {
        var result: UInt32 = 0
        for _ in 0..<4 {
            result = result << 8 | UInt32(try readByte(span, &offset, item: start))
        }
        return result
    }

    @inline(__always)
    private static func readUInt64(_ span: Span<UInt8>, _ offset: inout Int, item start: Int) throws -> UInt64 {
        var result: UInt64 = 0
        for _ in 0..<8 {
            result = result << 8 | UInt64(try readByte(span, &offset, item: start))
        }
        return result
    }

    /// The next `length` bytes, as a span, advancing `offset` past them.
    ///
    /// The result borrows from `span`. Swift 6.4 infers that; 6.3 needs it spelled
    /// out.
    @inline(__always)
    @_lifetime(copy span)
    private static func readSpan(
        _ length: UInt64,
        _ span: Span<UInt8>,
        _ offset: inout Int,
        item start: Int
    ) throws -> Span<UInt8> {
        guard let count = Int(exactly: length),
              count <= span.count - offset else {
            throw CBORError.unexpectedEnd(offset: start)
        }
        let end = offset + count
        let bytes = span.extracting(offset..<end)
        offset = end
        return bytes
    }

    /// Read `length` raw bytes, copying them into an array.
    private static func readBytes(
        _ length: UInt64,
        _ span: Span<UInt8>,
        _ offset: inout Int,
        item start: Int,
        source: ArraySlice<UInt8>?
    ) throws -> [UInt8] {
        let begin = offset
        let bytes = try readSpan(length, span, &offset, item: start)
        if let source {
            return Array(source[slice: begin..<offset])
        }
        return Array(capacity: bytes.count) { output in
            append(bytes, to: &output)
        }
    }

    /// Append `length` raw bytes to `bytes`, for a chunk of an indefinite-length
    /// string.
    private static func appendBytes(
        _ length: UInt64,
        _ span: Span<UInt8>,
        _ offset: inout Int,
        item start: Int,
        source: ArraySlice<UInt8>?,
        to bytes: inout [UInt8]
    ) throws {
        let begin = offset
        let chunk = try readSpan(length, span, &offset, item: start)
        if let source {
            bytes.append(contentsOf: source[slice: begin..<offset])
            return
        }
        bytes.append(addingCapacity: chunk.count) { output in
            append(chunk, to: &output)
        }
    }

    /// Copy `source` into `output`.
    ///
    /// An element-by-element loop, but one the optimizer turns into a block copy:
    /// it is about nine times faster than appending to an `Array` one byte at a
    /// time, and needs no unsafe pointers. (`Array(capacity:initializingWith:)` is
    /// back-deployed, so this runs on every supported OS.)
    @inline(__always)
    private static func append(_ source: Span<UInt8>, to output: inout OutputSpan<UInt8>) {
        for index in source.indices {
            output.append(source[index])
        }
    }

    private static func readTextString(
        _ length: UInt64,
        _ span: Span<UInt8>,
        _ offset: inout Int,
        item start: Int,
        source: ArraySlice<UInt8>?
    ) throws -> String {
        // Validate in place and copy once, rather than copying into an array
        // first and validating that.
        if #available(macOS 26.0, iOS 26.0, watchOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            let bytes = try readSpan(length, span, &offset, item: start)
            guard let utf8 = try? UTF8Span(validating: bytes) else {
                throw CBORError.invalidUTF8(offset: start)
            }
            return String(copying: utf8)
        }
        let raw = try readBytes(length, span, &offset, item: start, source: source)
        guard let string = validatedString(raw) else {
            throw CBORError.invalidUTF8(offset: start)
        }
        return string
    }

    /// Build a `String` from `bytes`, or return `nil` if they are not well-formed
    /// UTF-8.
    @inline(__always)
    private static func validatedString(_ bytes: some Collection<UInt8>) -> String? {
        if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
            return String(validating: bytes, as: UTF8.self)
        }
        return validatedStringBackDeployed(bytes)
    }

    /// `validatedString(_:)` for OSes that predate `String(validating:as:)`.
    ///
    /// `String(decoding:as:)` never fails: it replaces each ill-formed sequence with
    /// U+FFFD. That substitution always changes the bytes — the replacement is
    /// itself well-formed, so it can never coincide with the ill-formed input it
    /// stands in for — which means the input was valid exactly when decoding it
    /// round-trips unchanged.
    ///
    /// Internal rather than private so tests can exercise it on OSes where the
    /// `#available` check above never reaches it.
    static func validatedStringBackDeployed(_ bytes: some Collection<UInt8>) -> String? {
        let string = String(decoding: bytes, as: UTF8.self)
        return string.utf8.elementsEqual(bytes) ? string : nil
    }

    // MARK: Indefinite-length strings
    //
    // Indefinite byte/text strings only contain definite-length string chunks, so
    // they are read in a flat loop — no container frame or recursion needed.

    private static func readIndefiniteByteString(
        _ span: Span<UInt8>,
        _ offset: inout Int,
        item start: Int,
        source: ArraySlice<UInt8>?
    ) throws -> CBOR {
        var bytes: [UInt8] = []
        while true {
            let chunk = offset
            let initialByte = try readByte(span, &offset, item: chunk)
            if initialByte == 0xff { break }
            guard initialByte >> 5 == 2, initialByte & 0x1f != 31 else {
                throw CBORError.invalidIndefiniteLength(offset: chunk)
            }
            let length = try readArgument(initialByte & 0x1f, span, &offset, item: chunk)
            try appendBytes(length, span, &offset, item: chunk, source: source, to: &bytes)
        }
        return .byteString(bytes)
    }

    private static func readIndefiniteTextString(
        _ span: Span<UInt8>,
        _ offset: inout Int,
        item start: Int,
        source: ArraySlice<UInt8>?
    ) throws -> CBOR {
        var bytes: [UInt8] = []
        while true {
            let chunk = offset
            let initialByte = try readByte(span, &offset, item: chunk)
            if initialByte == 0xff { break }
            guard initialByte >> 5 == 3, initialByte & 0x1f != 31 else {
                throw CBORError.invalidIndefiniteLength(offset: chunk)
            }
            let length = try readArgument(initialByte & 0x1f, span, &offset, item: chunk)
            let chunkStart = bytes.count
            try appendBytes(length, span, &offset, item: chunk, source: source, to: &bytes)
            // Each definite text chunk must be valid UTF-8 on its own. A code
            // point split across two chunks is invalid even if their concatenation
            // is valid (RFC 8949 §3.2.3).
            guard validatedString(bytes[chunkStart...]) != nil else {
                throw CBORError.invalidUTF8(offset: chunk)
            }
        }
        guard let string = validatedString(bytes) else {
            throw CBORError.invalidUTF8(offset: start)
        }
        return .textString(string)
    }

    // MARK: Major type 7

    private static func parseSimpleOrFloat(
        _ additional: UInt8,
        _ span: Span<UInt8>,
        _ offset: inout Int,
        item start: Int
    ) throws -> CBOR {
        switch additional {
        case 0..<20:
            return .simple(CBORSimpleValue(unchecked: additional))
        case 20:
            return .bool(false)
        case 21:
            return .bool(true)
        case 22:
            return .null
        case 23:
            return .undefined
        case 24:
            let value = try readByte(span, &offset, item: start)
            // Simple values 0...31 must use the single-byte form, not 0xf8.
            guard value >= 32 else { throw CBORError.reservedAdditionalInfo(24, offset: start) }
            return .simple(CBORSimpleValue(unchecked: value))
        case 25:
            return .half(bitPattern: try readUInt16(span, &offset, item: start))
        case 26:
            return .float(Float(bitPattern: try readUInt32(span, &offset, item: start)))
        case 27:
            return .double(Double(bitPattern: try readUInt64(span, &offset, item: start)))
        case 31:
            // A break stop code where a data item was expected.
            throw CBORError.unexpectedBreak(offset: start)
        default: // 28, 29, 30
            throw CBORError.reservedAdditionalInfo(additional, offset: start)
        }
    }
}

extension ArraySlice {
    /// The elements at `offsets`, counted from `startIndex` as positions in its
    /// `span` are.
    @inline(__always)
    fileprivate subscript(slice offsets: Range<Int>) -> ArraySlice<Element> {
        self[(startIndex + offsets.lowerBound)..<(startIndex + offsets.upperBound)]
    }
}
