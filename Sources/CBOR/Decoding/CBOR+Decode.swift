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
        // Implemented in a later step.
        throw CBORUnimplementedError(symbol: "CBOR.decode(_:options:)")
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
        // Implemented in a later step.
        throw CBORUnimplementedError(symbol: "CBOR.decodeFirst(_:options:)")
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
