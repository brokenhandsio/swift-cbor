#if FoundationSupport
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#endif

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
        let encoder = _CBOREncoder(options: options)
        let cbor = try encoder.box(value)
        return cbor.encode(options: options)
    }
}

// MARK: - Intermediate node

/// A slot in an encoding container: either a finished value or a still-mutable
/// child container whose contents are materialized lazily.
private enum EncodingNode {
    case value(CBOR)
    case container(any EncodingContainerNode)

    var cbor: CBOR {
        switch self {
        case .value(let value): return value
        case .container(let node): return node.cbor
        }
    }
}

private protocol EncodingContainerNode: AnyObject {
    var cbor: CBOR { get }
}

// MARK: - Scalar conversions

private func cborFromSigned(_ value: Int64) -> CBOR {
    value < 0 ? .negativeInt(~UInt64(bitPattern: value)) : .unsignedInt(UInt64(value))
}

// MARK: - Encoder

private final class _CBOREncoder: Encoder {
    var codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }
    let options: CBOROptions

    private var topContainer: (any EncodingContainerNode)?

    init(options: CBOROptions, codingPath: [any CodingKey] = []) {
        self.options = options
        self.codingPath = codingPath
    }

    var cbor: CBOR { topContainer?.cbor ?? .null }

    /// Encode any `Encodable` value into a CBOR value, special-casing `Data`
    /// when Foundation support is enabled.
    func box<T: Encodable>(_ value: T) throws -> CBOR {
        #if FoundationSupport
        if let data = value as? Data {
            return .byteString([UInt8](data))
        }
        #endif
        let encoder = _CBOREncoder(options: options, codingPath: codingPath)
        try value.encode(to: encoder)
        return encoder.cbor
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let container = KeyedContainer<Key>(options: options, codingPath: codingPath)
        topContainer = container
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        let container = UnkeyedContainer(options: options, codingPath: codingPath)
        topContainer = container
        return container
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        let container = SingleValueContainer(options: options, codingPath: codingPath)
        topContainer = container
        return container
    }
}

/// Wraps a sub-encoder so its value is read lazily (used for `superEncoder`).
private final class EncoderNode: EncodingContainerNode {
    let encoder: _CBOREncoder
    init(_ encoder: _CBOREncoder) { self.encoder = encoder }
    var cbor: CBOR { encoder.cbor }
}

// MARK: - Keyed container

private final class KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol, EncodingContainerNode {
    let options: CBOROptions
    var codingPath: [any CodingKey]
    private var storage: [(key: CBOR, node: EncodingNode)] = []

    init(options: CBOROptions, codingPath: [any CodingKey]) {
        self.options = options
        self.codingPath = codingPath
    }

    var cbor: CBOR {
        var map: [CBOR: CBOR] = .init(minimumCapacity: storage.count)
        for entry in storage {
            map[entry.key] = entry.node.cbor
        }
        return .map(map)
    }

    private func append(_ node: EncodingNode, for key: Key) {
        storage.append((.textString(key.stringValue), node))
    }

    func encodeNil(forKey key: Key) { append(.value(.null), for: key) }
    func encode(_ value: Bool, forKey key: Key) { append(.value(.bool(value)), for: key) }
    func encode(_ value: String, forKey key: Key) { append(.value(.textString(value)), for: key) }
    func encode(_ value: Double, forKey key: Key) { append(.value(.double(value)), for: key) }
    func encode(_ value: Float, forKey key: Key) { append(.value(.float(value)), for: key) }
    func encode(_ value: Int, forKey key: Key) { append(.value(cborFromSigned(Int64(value))), for: key) }
    func encode(_ value: Int8, forKey key: Key) { append(.value(cborFromSigned(Int64(value))), for: key) }
    func encode(_ value: Int16, forKey key: Key) { append(.value(cborFromSigned(Int64(value))), for: key) }
    func encode(_ value: Int32, forKey key: Key) { append(.value(cborFromSigned(Int64(value))), for: key) }
    func encode(_ value: Int64, forKey key: Key) { append(.value(cborFromSigned(value)), for: key) }
    func encode(_ value: UInt, forKey key: Key) { append(.value(.unsignedInt(UInt64(value))), for: key) }
    func encode(_ value: UInt8, forKey key: Key) { append(.value(.unsignedInt(UInt64(value))), for: key) }
    func encode(_ value: UInt16, forKey key: Key) { append(.value(.unsignedInt(UInt64(value))), for: key) }
    func encode(_ value: UInt32, forKey key: Key) { append(.value(.unsignedInt(UInt64(value))), for: key) }
    func encode(_ value: UInt64, forKey key: Key) { append(.value(.unsignedInt(value)), for: key) }

    func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        let encoder = _CBOREncoder(options: options, codingPath: codingPath + [key])
        append(.value(try encoder.box(value)), for: key)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type, forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        let container = KeyedContainer<NestedKey>(options: options, codingPath: codingPath + [key])
        append(.container(container), for: key)
        return KeyedEncodingContainer(container)
    }

    func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        let container = UnkeyedContainer(options: options, codingPath: codingPath + [key])
        append(.container(container), for: key)
        return container
    }

    func superEncoder() -> any Encoder {
        superEncoder(forKey: Key(stringValue: "super")!)
    }

    func superEncoder(forKey key: Key) -> any Encoder {
        let encoder = _CBOREncoder(options: options, codingPath: codingPath + [key])
        append(.container(EncoderNode(encoder)), for: key)
        return encoder
    }
}

// MARK: - Unkeyed container

private final class UnkeyedContainer: UnkeyedEncodingContainer, EncodingContainerNode {
    let options: CBOROptions
    var codingPath: [any CodingKey]
    private var storage: [EncodingNode] = []

    init(options: CBOROptions, codingPath: [any CodingKey]) {
        self.options = options
        self.codingPath = codingPath
    }

    var count: Int { storage.count }

    var cbor: CBOR { .array(storage.map(\.cbor)) }

    func encodeNil() { storage.append(.value(.null)) }
    func encode(_ value: Bool) { storage.append(.value(.bool(value))) }
    func encode(_ value: String) { storage.append(.value(.textString(value))) }
    func encode(_ value: Double) { storage.append(.value(.double(value))) }
    func encode(_ value: Float) { storage.append(.value(.float(value))) }
    func encode(_ value: Int) { storage.append(.value(cborFromSigned(Int64(value)))) }
    func encode(_ value: Int8) { storage.append(.value(cborFromSigned(Int64(value)))) }
    func encode(_ value: Int16) { storage.append(.value(cborFromSigned(Int64(value)))) }
    func encode(_ value: Int32) { storage.append(.value(cborFromSigned(Int64(value)))) }
    func encode(_ value: Int64) { storage.append(.value(cborFromSigned(value))) }
    func encode(_ value: UInt) { storage.append(.value(.unsignedInt(UInt64(value)))) }
    func encode(_ value: UInt8) { storage.append(.value(.unsignedInt(UInt64(value)))) }
    func encode(_ value: UInt16) { storage.append(.value(.unsignedInt(UInt64(value)))) }
    func encode(_ value: UInt32) { storage.append(.value(.unsignedInt(UInt64(value)))) }
    func encode(_ value: UInt64) { storage.append(.value(.unsignedInt(value))) }

    func encode<T: Encodable>(_ value: T) throws {
        let encoder = _CBOREncoder(options: options, codingPath: codingPath)
        storage.append(.value(try encoder.box(value)))
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        let container = KeyedContainer<NestedKey>(options: options, codingPath: codingPath)
        storage.append(.container(container))
        return KeyedEncodingContainer(container)
    }

    func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        let container = UnkeyedContainer(options: options, codingPath: codingPath)
        storage.append(.container(container))
        return container
    }

    func superEncoder() -> any Encoder {
        let encoder = _CBOREncoder(options: options, codingPath: codingPath)
        storage.append(.container(EncoderNode(encoder)))
        return encoder
    }
}

// MARK: - Single-value container

private final class SingleValueContainer: SingleValueEncodingContainer, EncodingContainerNode {
    let options: CBOROptions
    var codingPath: [any CodingKey]
    private var node: EncodingNode = .value(.null)

    init(options: CBOROptions, codingPath: [any CodingKey]) {
        self.options = options
        self.codingPath = codingPath
    }

    var cbor: CBOR { node.cbor }

    func encodeNil() { node = .value(.null) }
    func encode(_ value: Bool) { node = .value(.bool(value)) }
    func encode(_ value: String) { node = .value(.textString(value)) }
    func encode(_ value: Double) { node = .value(.double(value)) }
    func encode(_ value: Float) { node = .value(.float(value)) }
    func encode(_ value: Int) { node = .value(cborFromSigned(Int64(value))) }
    func encode(_ value: Int8) { node = .value(cborFromSigned(Int64(value))) }
    func encode(_ value: Int16) { node = .value(cborFromSigned(Int64(value))) }
    func encode(_ value: Int32) { node = .value(cborFromSigned(Int64(value))) }
    func encode(_ value: Int64) { node = .value(cborFromSigned(value)) }
    func encode(_ value: UInt) { node = .value(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt8) { node = .value(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt16) { node = .value(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt32) { node = .value(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt64) { node = .value(.unsignedInt(value)) }

    func encode<T: Encodable>(_ value: T) throws {
        let encoder = _CBOREncoder(options: options, codingPath: codingPath)
        node = .value(try encoder.box(value))
    }
}
