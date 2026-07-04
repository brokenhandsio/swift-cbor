extension CBOR {
    /// Decode exactly one CBOR data item from `bytes`, requiring that the entire
    /// input is consumed.
    ///
    /// - Parameters:
    ///   - bytes: A borrowed view of the CBOR-encoded bytes.
    ///   - options: Decoding options (depth limit, duplicate-key policy).
    /// - Returns: The decoded value.
    /// - Throws: ``CBORError`` on malformed input, on trailing data, or when the
    ///   depth limit is exceeded.
    public static func decode(
        _ bytes: Span<UInt8>,
        options: CBOROptions = .default
    ) throws -> CBOR {
        var offset = 0
        let value = try CBORParser.parseItem(bytes, &offset, options: options)
        guard offset == bytes.count else {
            throw CBORError.trailingData(remaining: bytes.count - offset)
        }
        return value
    }

    /// Decode the first CBOR data item from `bytes`, allowing and reporting trailing
    /// bytes.
    ///
    /// This is useful when a CBOR item is embedded in a larger buffer and the caller
    /// needs to know how many bytes it occupied — for example to slice out a value
    /// that immediately follows it.
    ///
    /// - Returns: The decoded value and the number of bytes it consumed from the
    ///   start of `bytes`.
    public static func decodeFirst(
        _ bytes: Span<UInt8>,
        options: CBOROptions = .default
    ) throws -> (value: CBOR, bytesConsumed: Int) {
        var offset = 0
        let value = try CBORParser.parseItem(bytes, &offset, options: options)
        return (value, offset)
    }
}

// MARK: - Convenience overloads over common byte containers

extension CBOR {
    /// Decode exactly one CBOR data item from an array of bytes.
    public static func decode(
        _ bytes: [UInt8],
        options: CBOROptions = .default
    ) throws -> CBOR {
        try decode(bytes.span, options: options)
    }

    /// Decode exactly one CBOR data item from a slice of bytes.
    public static func decode(
        _ bytes: ArraySlice<UInt8>,
        options: CBOROptions = .default
    ) throws -> CBOR {
        try decode(bytes.span, options: options)
    }

    /// Decode the first CBOR data item from an array of bytes, reporting how many
    /// bytes it consumed.
    public static func decodeFirst(
        _ bytes: [UInt8],
        options: CBOROptions = .default
    ) throws -> (value: CBOR, bytesConsumed: Int) {
        try decodeFirst(bytes.span, options: options)
    }

    /// Decode the first CBOR data item from a slice of bytes, reporting how many
    /// bytes it consumed.
    public static func decodeFirst(
        _ bytes: ArraySlice<UInt8>,
        options: CBOROptions = .default
    ) throws -> (value: CBOR, bytesConsumed: Int) {
        try decodeFirst(bytes.span, options: options)
    }
}
