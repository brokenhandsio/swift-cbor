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
        var out: [UInt8] = []
        out.reserveCapacity(64)
        #if FoundationSupport
        if let data = value as? Data {
            appendTypedArgument(major: 2, UInt64(data.count), to: &out)
            out.append(contentsOf: data)
            return out
        }
        #endif
        let encoder = _CBOREncoder(options: options)
        try value.encode(to: encoder)
        encoder.write(to: &out, options: options)
        return out
    }
}

// MARK: - Intermediate node
//
// The containers build a shallow tree of nodes as the value is encoded, then write
// their CBOR bytes directly into the output buffer in a single pass — there is no
// intermediate `CBOR` value tree and no second traversal.

private enum EncodingNode {
    case scalar(CBOR)
    case container(any EncodingContainerNode)

    func write(to out: inout [UInt8], options: CBOROptions) {
        switch self {
        // A `.scalar` node is always a leaf CBOR value, so it can be written directly
        // without spinning up the iterative encoder's work stack.
        case .scalar(let value): value.appendScalarBytes(to: &out)
        case .container(let node): node.write(to: &out, options: options)
        }
    }
}

private protocol EncodingContainerNode: AnyObject {
    func write(to out: inout [UInt8], options: CBOROptions)
}

// MARK: - Scalar conversions

private func cborFromSigned(_ value: Int64) -> CBOR {
    value < 0 ? .negativeInt(~UInt64(bitPattern: value)) : .unsignedInt(UInt64(value))
}

/// Encode a nested `Encodable` value into a node, special-casing `Data`.
private func boxNode<T: Encodable>(
    _ value: T, options: CBOROptions, codingPath: [any CodingKey]
) throws -> EncodingNode {
    #if FoundationSupport
    if let data = value as? Data {
        return .scalar(.byteString([UInt8](data)))
    }
    #endif
    let encoder = _CBOREncoder(options: options, codingPath: codingPath)
    try value.encode(to: encoder)
    return encoder.asNode
}

/// Write a keyed container's entries as a CBOR map, sorted into RFC 8949 §4.2.1
/// canonical order when deterministic. Keys are encoded once into a shared scratch
/// buffer and sorted by byte range — no per-key allocation, no per-value buffering.
private func writeMap(
    _ entries: [(key: CBOR, node: EncodingNode)],
    to out: inout [UInt8],
    options: CBOROptions
) {
    // Keyed-container keys are always text-string scalars, so they can be written
    // with `appendScalarBytes` (no work stack).
    appendTypedArgument(major: 5, UInt64(entries.count), to: &out)
    guard options.deterministic else {
        for entry in entries {
            entry.key.appendScalarBytes(to: &out)
            entry.node.write(to: &out, options: options)
        }
        return
    }
    var keyBytes: [UInt8] = []
    var ranges: [(start: Int, end: Int, index: Int)] = []
    ranges.reserveCapacity(entries.count)
    for (index, entry) in entries.enumerated() {
        let start = keyBytes.count
        entry.key.appendScalarBytes(to: &keyBytes)
        ranges.append((start, keyBytes.count, index))
    }
    ranges.sort { keyRangeIsOrderedBefore(keyBytes, $0.start, $0.end, $1.start, $1.end) }
    for range in ranges {
        out.append(contentsOf: keyBytes[range.start..<range.end])
        entries[range.index].node.write(to: &out, options: options)
    }
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

    /// This encoder's result as a node (for nesting), or `null` if nothing was encoded.
    var asNode: EncodingNode {
        if let topContainer { return .container(topContainer) }
        return .scalar(.null)
    }

    func write(to out: inout [UInt8], options: CBOROptions) {
        if let topContainer {
            topContainer.write(to: &out, options: options)
        } else {
            out.append(0xf6) // null
        }
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

/// Wraps a sub-encoder so its bytes are written lazily (used for `superEncoder`).
private final class EncoderNode: EncodingContainerNode {
    let encoder: _CBOREncoder
    init(_ encoder: _CBOREncoder) { self.encoder = encoder }
    func write(to out: inout [UInt8], options: CBOROptions) {
        encoder.write(to: &out, options: options)
    }
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

    func write(to out: inout [UInt8], options: CBOROptions) {
        writeMap(storage, to: &out, options: options)
    }

    private func append(_ node: EncodingNode, for key: Key) {
        storage.append((.textString(key.stringValue), node))
    }

    func encodeNil(forKey key: Key) { append(.scalar(.null), for: key) }
    func encode(_ value: Bool, forKey key: Key) { append(.scalar(.bool(value)), for: key) }
    func encode(_ value: String, forKey key: Key) { append(.scalar(.textString(value)), for: key) }
    func encode(_ value: Double, forKey key: Key) { append(.scalar(.double(value)), for: key) }
    func encode(_ value: Float, forKey key: Key) { append(.scalar(.float(value)), for: key) }
    func encode(_ value: Int, forKey key: Key) { append(.scalar(cborFromSigned(Int64(value))), for: key) }
    func encode(_ value: Int8, forKey key: Key) { append(.scalar(cborFromSigned(Int64(value))), for: key) }
    func encode(_ value: Int16, forKey key: Key) { append(.scalar(cborFromSigned(Int64(value))), for: key) }
    func encode(_ value: Int32, forKey key: Key) { append(.scalar(cborFromSigned(Int64(value))), for: key) }
    func encode(_ value: Int64, forKey key: Key) { append(.scalar(cborFromSigned(value)), for: key) }
    func encode(_ value: UInt, forKey key: Key) { append(.scalar(.unsignedInt(UInt64(value))), for: key) }
    func encode(_ value: UInt8, forKey key: Key) { append(.scalar(.unsignedInt(UInt64(value))), for: key) }
    func encode(_ value: UInt16, forKey key: Key) { append(.scalar(.unsignedInt(UInt64(value))), for: key) }
    func encode(_ value: UInt32, forKey key: Key) { append(.scalar(.unsignedInt(UInt64(value))), for: key) }
    func encode(_ value: UInt64, forKey key: Key) { append(.scalar(.unsignedInt(value)), for: key) }

    func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        append(try boxNode(value, options: options, codingPath: codingPath + [key]), for: key)
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

    func write(to out: inout [UInt8], options: CBOROptions) {
        appendTypedArgument(major: 4, UInt64(storage.count), to: &out)
        for node in storage {
            node.write(to: &out, options: options)
        }
    }

    func encodeNil() { storage.append(.scalar(.null)) }
    func encode(_ value: Bool) { storage.append(.scalar(.bool(value))) }
    func encode(_ value: String) { storage.append(.scalar(.textString(value))) }
    func encode(_ value: Double) { storage.append(.scalar(.double(value))) }
    func encode(_ value: Float) { storage.append(.scalar(.float(value))) }
    func encode(_ value: Int) { storage.append(.scalar(cborFromSigned(Int64(value)))) }
    func encode(_ value: Int8) { storage.append(.scalar(cborFromSigned(Int64(value)))) }
    func encode(_ value: Int16) { storage.append(.scalar(cborFromSigned(Int64(value)))) }
    func encode(_ value: Int32) { storage.append(.scalar(cborFromSigned(Int64(value)))) }
    func encode(_ value: Int64) { storage.append(.scalar(cborFromSigned(value))) }
    func encode(_ value: UInt) { storage.append(.scalar(.unsignedInt(UInt64(value)))) }
    func encode(_ value: UInt8) { storage.append(.scalar(.unsignedInt(UInt64(value)))) }
    func encode(_ value: UInt16) { storage.append(.scalar(.unsignedInt(UInt64(value)))) }
    func encode(_ value: UInt32) { storage.append(.scalar(.unsignedInt(UInt64(value)))) }
    func encode(_ value: UInt64) { storage.append(.scalar(.unsignedInt(value))) }

    func encode<T: Encodable>(_ value: T) throws {
        storage.append(try boxNode(value, options: options, codingPath: codingPath))
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
    private var node: EncodingNode = .scalar(.null)

    init(options: CBOROptions, codingPath: [any CodingKey]) {
        self.options = options
        self.codingPath = codingPath
    }

    func write(to out: inout [UInt8], options: CBOROptions) {
        node.write(to: &out, options: options)
    }

    func encodeNil() { node = .scalar(.null) }
    func encode(_ value: Bool) { node = .scalar(.bool(value)) }
    func encode(_ value: String) { node = .scalar(.textString(value)) }
    func encode(_ value: Double) { node = .scalar(.double(value)) }
    func encode(_ value: Float) { node = .scalar(.float(value)) }
    func encode(_ value: Int) { node = .scalar(cborFromSigned(Int64(value))) }
    func encode(_ value: Int8) { node = .scalar(cborFromSigned(Int64(value))) }
    func encode(_ value: Int16) { node = .scalar(cborFromSigned(Int64(value))) }
    func encode(_ value: Int32) { node = .scalar(cborFromSigned(Int64(value))) }
    func encode(_ value: Int64) { node = .scalar(cborFromSigned(value)) }
    func encode(_ value: UInt) { node = .scalar(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt8) { node = .scalar(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt16) { node = .scalar(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt32) { node = .scalar(.unsignedInt(UInt64(value))) }
    func encode(_ value: UInt64) { node = .scalar(.unsignedInt(value)) }

    func encode<T: Encodable>(_ value: T) throws {
        node = try boxNode(value, options: options, codingPath: codingPath)
    }
}
