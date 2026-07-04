#if FoundationSupport
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#endif

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
        let cbor = try CBOR.decode(bytes, options: options)
        let decoder = _CBORDecoder(cbor: cbor, options: options)
        return try decoder.unbox(cbor, as: type)
    }

    /// Decode a value of the given type from a slice of CBOR bytes.
    public func decode<T: Decodable>(_ type: T.Type = T.self, from bytes: ArraySlice<UInt8>) throws -> T {
        try decode(type, from: Array(bytes))
    }
}

// MARK: - Decoder

private final class _CBORDecoder: Decoder {
    let cbor: CBOR
    let options: CBOROptions
    var codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    init(cbor: CBOR, options: CBOROptions, codingPath: [any CodingKey] = []) {
        self.cbor = cbor
        self.options = options
        self.codingPath = codingPath
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .map(let map) = cbor else {
            throw typeMismatch([String: Any].self, cbor, codingPath)
        }
        return KeyedDecodingContainer(KeyedContainer<Key>(map: map, options: options, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case .array(let array) = cbor else {
            throw typeMismatch([Any].self, cbor, codingPath)
        }
        return UnkeyedContainer(array: array, options: options, codingPath: codingPath)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        SingleValueContainer(cbor: cbor, options: options, codingPath: codingPath)
    }

    /// Decode any `Decodable` type from a CBOR value, special-casing `Data`
    /// when Foundation support is enabled.
    func unbox<T: Decodable>(_ cbor: CBOR, as type: T.Type) throws -> T {
        #if FoundationSupport
        if type == Data.self {
            guard case .byteString(let bytes) = cbor else {
                throw typeMismatch(Data.self, cbor, codingPath)
            }
            return Data(bytes) as! T
        }
        #endif
        let decoder = _CBORDecoder(cbor: cbor, options: options, codingPath: codingPath)
        return try T(from: decoder)
    }
}

// MARK: - Errors

private func typeMismatch(_ type: Any.Type, _ cbor: CBOR, _ codingPath: [any CodingKey]) -> DecodingError {
    DecodingError.typeMismatch(type, DecodingError.Context(
        codingPath: codingPath,
        debugDescription: "Expected to decode \(type) but found \(cbor) instead."
    ))
}

private func outOfRange(_ type: Any.Type, _ codingPath: [any CodingKey]) -> DecodingError {
    DecodingError.dataCorrupted(DecodingError.Context(
        codingPath: codingPath,
        debugDescription: "Parsed CBOR number does not fit in \(type)."
    ))
}

// MARK: - Scalar unboxing

private func unboxBool(_ cbor: CBOR, _ codingPath: [any CodingKey]) throws -> Bool {
    guard case .bool(let value) = cbor else { throw typeMismatch(Bool.self, cbor, codingPath) }
    return value
}

private func unboxString(_ cbor: CBOR, _ codingPath: [any CodingKey]) throws -> String {
    guard case .textString(let value) = cbor else { throw typeMismatch(String.self, cbor, codingPath) }
    return value
}

private func unboxDouble(_ cbor: CBOR, _ codingPath: [any CodingKey]) throws -> Double {
    switch cbor {
    case .half(let value): return Double(value)
    case .float(let value): return Double(value)
    case .double(let value): return value
    default: throw typeMismatch(Double.self, cbor, codingPath)
    }
}

private func unboxFloat(_ cbor: CBOR, _ codingPath: [any CodingKey]) throws -> Float {
    switch cbor {
    case .half(let value): return Float(value)
    case .float(let value): return value
    case .double(let value): return Float(value)
    default: throw typeMismatch(Float.self, cbor, codingPath)
    }
}

private func unboxSigned<T: FixedWidthInteger & SignedInteger>(
    _ cbor: CBOR, _ type: T.Type, _ codingPath: [any CodingKey]
) throws -> T {
    let signed: Int64
    switch cbor {
    case .unsignedInt(let value):
        guard let fitted = Int64(exactly: value) else { throw outOfRange(type, codingPath) }
        signed = fitted
    case .negativeInt(let argument):
        guard let fitted = Int64(exactly: argument) else { throw outOfRange(type, codingPath) }
        signed = -1 - fitted
    default:
        throw typeMismatch(type, cbor, codingPath)
    }
    guard let result = T(exactly: signed) else { throw outOfRange(type, codingPath) }
    return result
}

private func unboxUnsigned<T: FixedWidthInteger & UnsignedInteger>(
    _ cbor: CBOR, _ type: T.Type, _ codingPath: [any CodingKey]
) throws -> T {
    guard case .unsignedInt(let value) = cbor else { throw typeMismatch(type, cbor, codingPath) }
    guard let result = T(exactly: value) else { throw outOfRange(type, codingPath) }
    return result
}

// MARK: - Keyed container

private struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let map: [CBOR: CBOR]
    let options: CBOROptions
    let codingPath: [any CodingKey]

    var allKeys: [Key] {
        map.keys.compactMap { key in
            switch key {
            case .textString(let string): return Key(stringValue: string)
            case .unsignedInt(let value): return Int(exactly: value).flatMap(Key.init(intValue:))
            default: return nil
            }
        }
    }

    private func find(_ key: Key) throws -> CBOR {
        guard let value = map[.textString(key.stringValue)] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "No value associated with key \(key.stringValue)."
            ))
        }
        return value
    }

    private func path(_ key: Key) -> [any CodingKey] { codingPath + [key] }

    func contains(_ key: Key) -> Bool {
        map[.textString(key.stringValue)] != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        try find(key).isNull
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try unboxBool(find(key), path(key)) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try unboxString(find(key), path(key)) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try unboxDouble(find(key), path(key)) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try unboxFloat(find(key), path(key)) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try unboxSigned(find(key), type, path(key)) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try unboxSigned(find(key), type, path(key)) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try unboxSigned(find(key), type, path(key)) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try unboxSigned(find(key), type, path(key)) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try unboxSigned(find(key), type, path(key)) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try unboxUnsigned(find(key), type, path(key)) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try unboxUnsigned(find(key), type, path(key)) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try unboxUnsigned(find(key), type, path(key)) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try unboxUnsigned(find(key), type, path(key)) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try unboxUnsigned(find(key), type, path(key)) }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let value = try find(key)
        let decoder = _CBORDecoder(cbor: value, options: options, codingPath: path(key))
        return try decoder.unbox(value, as: type)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type, forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let decoder = _CBORDecoder(cbor: try find(key), options: options, codingPath: path(key))
        return try decoder.container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        let decoder = _CBORDecoder(cbor: try find(key), options: options, codingPath: path(key))
        return try decoder.unkeyedContainer()
    }

    func superDecoder() throws -> any Decoder {
        _CBORDecoder(cbor: map[.textString("super")] ?? .null, options: options, codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        _CBORDecoder(cbor: try find(key), options: options, codingPath: path(key))
    }
}

// MARK: - Unkeyed container

private final class UnkeyedContainer: UnkeyedDecodingContainer {
    let array: [CBOR]
    let options: CBOROptions
    let codingPath: [any CodingKey]
    var currentIndex = 0

    init(array: [CBOR], options: CBOROptions, codingPath: [any CodingKey]) {
        self.array = array
        self.options = options
        self.codingPath = codingPath
    }

    var count: Int? { array.count }
    var isAtEnd: Bool { currentIndex >= array.count }

    private func next(_ type: Any.Type) throws -> CBOR {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Unkeyed container is at end."
            ))
        }
        let value = array[currentIndex]
        currentIndex += 1
        return value
    }

    func decodeNil() throws -> Bool {
        guard !isAtEnd else { return false }
        if array[currentIndex].isNull {
            currentIndex += 1
            return true
        }
        return false
    }

    func decode(_ type: Bool.Type) throws -> Bool { try unboxBool(next(type), codingPath) }
    func decode(_ type: String.Type) throws -> String { try unboxString(next(type), codingPath) }
    func decode(_ type: Double.Type) throws -> Double { try unboxDouble(next(type), codingPath) }
    func decode(_ type: Float.Type) throws -> Float { try unboxFloat(next(type), codingPath) }
    func decode(_ type: Int.Type) throws -> Int { try unboxSigned(next(type), type, codingPath) }
    func decode(_ type: Int8.Type) throws -> Int8 { try unboxSigned(next(type), type, codingPath) }
    func decode(_ type: Int16.Type) throws -> Int16 { try unboxSigned(next(type), type, codingPath) }
    func decode(_ type: Int32.Type) throws -> Int32 { try unboxSigned(next(type), type, codingPath) }
    func decode(_ type: Int64.Type) throws -> Int64 { try unboxSigned(next(type), type, codingPath) }
    func decode(_ type: UInt.Type) throws -> UInt { try unboxUnsigned(next(type), type, codingPath) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try unboxUnsigned(next(type), type, codingPath) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try unboxUnsigned(next(type), type, codingPath) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try unboxUnsigned(next(type), type, codingPath) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try unboxUnsigned(next(type), type, codingPath) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let value = try next(type)
        let decoder = _CBORDecoder(cbor: value, options: options, codingPath: codingPath)
        return try decoder.unbox(value, as: type)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let decoder = _CBORDecoder(cbor: try next(type), options: options, codingPath: codingPath)
        return try decoder.container(keyedBy: type)
    }

    func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        let decoder = _CBORDecoder(cbor: try next([Any].self), options: options, codingPath: codingPath)
        return try decoder.unkeyedContainer()
    }

    func superDecoder() throws -> any Decoder {
        _CBORDecoder(cbor: try next((any Decoder).self), options: options, codingPath: codingPath)
    }
}

// MARK: - Single-value container

private struct SingleValueContainer: SingleValueDecodingContainer {
    let cbor: CBOR
    let options: CBOROptions
    let codingPath: [any CodingKey]

    func decodeNil() -> Bool { cbor.isNull }

    func decode(_ type: Bool.Type) throws -> Bool { try unboxBool(cbor, codingPath) }
    func decode(_ type: String.Type) throws -> String { try unboxString(cbor, codingPath) }
    func decode(_ type: Double.Type) throws -> Double { try unboxDouble(cbor, codingPath) }
    func decode(_ type: Float.Type) throws -> Float { try unboxFloat(cbor, codingPath) }
    func decode(_ type: Int.Type) throws -> Int { try unboxSigned(cbor, type, codingPath) }
    func decode(_ type: Int8.Type) throws -> Int8 { try unboxSigned(cbor, type, codingPath) }
    func decode(_ type: Int16.Type) throws -> Int16 { try unboxSigned(cbor, type, codingPath) }
    func decode(_ type: Int32.Type) throws -> Int32 { try unboxSigned(cbor, type, codingPath) }
    func decode(_ type: Int64.Type) throws -> Int64 { try unboxSigned(cbor, type, codingPath) }
    func decode(_ type: UInt.Type) throws -> UInt { try unboxUnsigned(cbor, type, codingPath) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try unboxUnsigned(cbor, type, codingPath) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try unboxUnsigned(cbor, type, codingPath) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try unboxUnsigned(cbor, type, codingPath) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try unboxUnsigned(cbor, type, codingPath) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let decoder = _CBORDecoder(cbor: cbor, options: options, codingPath: codingPath)
        return try decoder.unbox(cbor, as: type)
    }
}
