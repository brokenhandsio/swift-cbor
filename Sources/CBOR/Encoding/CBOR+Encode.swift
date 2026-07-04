extension CBOR {
    /// Encode this data item to its CBOR byte representation.
    ///
    /// Encoding never fails: every `CBOR` value has a byte representation. When
    /// `options.deterministic` is set (the default), integers and floats use their
    /// shortest form and map keys are emitted in RFC 8949 §4.2 canonical order.
    ///
    /// - Parameter options: Encoding options.
    /// - Returns: The encoded bytes.
    public func encode(options: CBOROptions = .default) -> [UInt8] {
        // Implemented in a later step. `encode` cannot throw, so until then it
        // returns an empty buffer; dependent tests fail rather than trap.
        []
    }
}
