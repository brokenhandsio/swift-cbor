/// Encodes Swift `Encodable` values to CBOR bytes, mirroring `JSONEncoder`.
///
/// ```swift
/// let bytes = try CBOREncoder().encode(myValue)
/// ```
public struct CBOREncoder: Sendable {
    /// Options applied when producing the CBOR bytes.
    public var options: CBOROptions

    public init(options: CBOROptions = .default) {
        self.options = options
    }

    /// Encode a value to CBOR bytes.
    public func encode<T: Encodable>(_ value: T) throws -> [UInt8] {
        // Implemented in a later step.
        throw CBORUnimplementedError(symbol: "CBOREncoder.encode(_:)")
    }
}
