/// Decodes CBOR bytes into Swift `Decodable` values, mirroring `JSONDecoder`.
///
/// ```swift
/// let value = try CBORDecoder().decode(MyType.self, from: bytes)
/// ```
public struct CBORDecoder: Sendable {
    /// Options applied when reading the CBOR bytes.
    public var options: CBOROptions

    public init(options: CBOROptions = .default) {
        self.options = options
    }

    /// Decode a value of the given type from CBOR bytes.
    public func decode<T: Decodable>(_ type: T.Type = T.self, from bytes: [UInt8]) throws -> T {
        // Implemented in a later step.
        fatalError("CBORDecoder.decode(_:from:) is not implemented yet")
    }

    /// Decode a value of the given type from a slice of CBOR bytes.
    public func decode<T: Decodable>(_ type: T.Type = T.self, from bytes: ArraySlice<UInt8>) throws -> T {
        try decode(type, from: Array(bytes))
    }
}
