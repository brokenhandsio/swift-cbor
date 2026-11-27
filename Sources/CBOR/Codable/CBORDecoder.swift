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
///
/// A keyed container looks a key up by its `stringValue`, which is what
/// ``CBOREncoder`` writes. If that is absent and the key has an `intValue`, it then
/// tries the integer, so types whose `CodingKeys` have `Int` raw values can decode
/// integer-keyed maps such as COSE keys.
///
/// With the `FoundationSupport` trait (the default), `Data` decodes from a byte
/// string and `Date` from a number of seconds since 1970-01-01T00:00Z, either
/// wrapped in tag 1 as ``CBOREncoder`` writes it or bare, as protocols such as
/// CWT (RFC 8392) write timestamps. Text dates (tag 0) are not decoded as `Date`.
public struct CBORDecoder: Sendable {
    /// Options applied when reading the CBOR bytes.
    public var options: CBORDecodingOptions

    /// Maximum number of nested `Decodable.init(from:)` calls. Defaults to `128`.
    ///
    /// This is separate from ``CBORDecodingOptions/maximumDepth``: a single
    /// recursive Swift model can use several stack frames per CBOR container.
    /// Exceeding this limit throws `DecodingError.dataCorrupted`. Raising it can
    /// exhaust a small thread stack, depending on the decoded type and build.
    public var maximumCodableDepth: Int

    /// Create a decoder.
    ///
    /// - Parameters:
    ///   - options: How to parse the CBOR bytes.
    ///   - maximumCodableDepth: Maximum nested generic `Decodable` calls.
    public init(options: CBORDecodingOptions = .default, maximumCodableDepth: Int = 128) {
        self.options = options
        self.maximumCodableDepth = maximumCodableDepth
    }

    /// Decode a value of the given type from CBOR bytes.
    public func decode<T: Decodable>(_ type: T.Type = T.self, from bytes: [UInt8]) throws -> T {
        try decode(type, fromValue: CBOR.decode(bytes, options: options))
    }

    /// Decode a value of the given type from a slice of CBOR bytes.
    ///
    /// The slice is read in place rather than copied.
    public func decode<T: Decodable>(_ type: T.Type = T.self, from bytes: ArraySlice<UInt8>) throws -> T {
        try decode(type, fromValue: CBOR.decode(bytes, options: options))
    }

    private func decode<T: Decodable>(_ type: T.Type, fromValue cbor: CBOR) throws -> T {
        try _CBORDecoder(cbor: cbor, options: options, maximumCodableDepth: maximumCodableDepth)
            .unbox(as: type)
    }
}

// MARK: - Decoder

/// A decoder's position below its parent: the key or index it was reached by.
private enum PathComponent {
    case root
    case key(any CodingKey)
    case index(Int)
}

private final class _CBORDecoder: Decoder {
    let cbor: CBOR
    let options: CBORDecodingOptions
    let maximumCodableDepth: Int
    private var activeCodableDepth: Int
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    // The coding path is held as a link to the parent decoder plus this decoder's
    // own step, and only assembled into an array when something asks for it — an
    // error, or user code reading `codingPath`. Building `codingPath + [key]` for
    // every nested value instead would cost an allocation each time, which for an
    // array of scalars roughly doubles the allocations of decoding it.
    private let parent: _CBORDecoder?
    private let component: PathComponent

    init(
        cbor: CBOR,
        options: CBORDecodingOptions,
        maximumCodableDepth: Int,
        parent: _CBORDecoder? = nil,
        component: PathComponent = .root
    ) {
        self.cbor = cbor
        self.options = options
        self.maximumCodableDepth = maximumCodableDepth
        self.activeCodableDepth = parent?.activeCodableDepth ?? 0
        self.parent = parent
        self.component = component
    }

    var codingPath: [any CodingKey] {
        var reversedPath: [any CodingKey] = []
        var node: _CBORDecoder? = self
        while let current = node {
            switch current.component {
            case .root: break
            case .key(let key): reversedPath.append(key)
            case .index(let index): reversedPath.append(PathKey(index: index))
            }
            node = current.parent
        }
        return reversedPath.reversed()
    }

    /// A decoder for `value`, reached from this one by `component`.
    func child(_ value: CBOR, at component: PathComponent) -> _CBORDecoder {
        _CBORDecoder(
            cbor: value, options: options,
            maximumCodableDepth: maximumCodableDepth, parent: self, component: component
        )
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .map(let map) = cbor else {
            throw typeMismatch([String: Any].self, cbor, codingPath)
        }
        return KeyedDecodingContainer(KeyedContainer<Key>(map: map, decoder: self))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case .array(let array) = cbor else {
            throw typeMismatch([Any].self, cbor, codingPath)
        }
        return UnkeyedContainer(array: array, decoder: self)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        SingleValueContainer(decoder: self)
    }

    /// Decode any `Decodable` type from this decoder's value, special-casing `Data`
    /// and `Date` when Foundation support is enabled.
    func unbox<T: Decodable>(as type: T.Type) throws -> T {
        #if FoundationSupport
        if type == Data.self {
            guard case .byteString(let bytes) = cbor else {
                throw typeMismatch(Data.self, cbor, codingPath)
            }
            return Data(bytes) as! T
        }
        if type == Date.self {
            guard let seconds = epochSeconds(cbor) else {
                throw typeMismatch(Date.self, cbor, codingPath)
            }
            return Date(timeIntervalSince1970: seconds) as! T
        }
        #endif
        guard activeCodableDepth < maximumCodableDepth else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Decodable nesting exceeds the limit of \(maximumCodableDepth)."
            ))
        }
        activeCodableDepth += 1
        defer { activeCodableDepth -= 1 }
        return try T(from: self)
    }
}

/// A coding-path entry the decoder supplies itself: an array index, or `super`.
private struct PathKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.init(index: intValue)
    }

    /// Named the way `JSONDecoder` names indices, so paths read the same.
    init(index: Int) {
        self.stringValue = "Index \(index)"
        self.intValue = index
    }

    static let `super` = PathKey(stringValue: "super")
}

#if FoundationSupport
/// Seconds since 1970 from tag 1 epoch time (RFC 8949 §3.4.2) or a bare number,
/// or `nil` if the value is neither.
private func epochSeconds(_ cbor: CBOR) -> Double? {
    var content = cbor
    if case .tagged(.epochDateTime, let inner) = cbor {
        content = inner
    }
    switch content {
    case .unsignedInt(let value):
        return Double(value)
    case .negativeInt(let value):
        return -1 - Double(value)
    default:
        return content.doubleValue
    }
}
#endif

// MARK: - Errors

private func typeMismatch(_ type: Any.Type, _ cbor: CBOR, _ codingPath: [any CodingKey]) -> DecodingError {
    DecodingError.typeMismatch(type, DecodingError.Context(
        codingPath: codingPath,
        debugDescription: "Expected to decode \(type) but found \(kind(of: cbor)) instead."
    ))
}

/// What kind of item `cbor` is, for an error message. The value itself is left
/// out, as `JSONDecoder` leaves it out: it can be large, and it comes from the
/// input, so it doesn't belong in logs.
private func kind(of cbor: CBOR) -> String {
    switch cbor {
    case .unsignedInt: "an unsigned integer"
    case .negativeInt: "a negative integer"
    case .byteString: "a byte string"
    case .textString: "a text string"
    case .array: "an array"
    case .map: "a map"
    case .tagged(let tag, _): "an item with tag \(tag.rawValue)"
    case .simple: "a simple value"
    case .bool: "a Boolean"
    case .null: "null"
    case .undefined: "undefined"
    case .half: "a half-precision float"
    case .float: "a single-precision float"
    case .double: "a double-precision float"
    }
}

private func outOfRange(_ type: Any.Type, _ codingPath: [any CodingKey]) -> DecodingError {
    DecodingError.dataCorrupted(DecodingError.Context(
        codingPath: codingPath,
        debugDescription: "Parsed CBOR number does not fit in \(type)."
    ))
}

// MARK: - Scalar unboxing
//
// Each helper takes the coding path as an autoclosure so the path — which costs an
// allocation to build — is only built when a value fails to decode.

@inline(__always)
private func unboxBool(_ cbor: CBOR, _ codingPath: @autoclosure () -> [any CodingKey]) throws -> Bool {
    guard case .bool(let value) = cbor else { throw typeMismatch(Bool.self, cbor, codingPath()) }
    return value
}

@inline(__always)
private func unboxString(_ cbor: CBOR, _ codingPath: @autoclosure () -> [any CodingKey]) throws -> String {
    guard case .textString(let value) = cbor else { throw typeMismatch(String.self, cbor, codingPath()) }
    return value
}

@inline(__always)
private func unboxDouble(_ cbor: CBOR, _ codingPath: @autoclosure () -> [any CodingKey]) throws -> Double {
    switch cbor {
    case .half(let bits): return HalfPrecision.double(fromBits: bits)
    case .float(let value): return Double(value)
    case .double(let value): return value
    default: throw typeMismatch(Double.self, cbor, codingPath())
    }
}

@inline(__always)
private func unboxFloat(_ cbor: CBOR, _ codingPath: @autoclosure () -> [any CodingKey]) throws -> Float {
    switch cbor {
    case .half(let bits): return HalfPrecision.float(fromBits: bits)
    case .float(let value): return value
    case .double(let value): return Float(value)
    default: throw typeMismatch(Float.self, cbor, codingPath())
    }
}

@inline(__always)
private func unboxSigned<T: FixedWidthInteger & SignedInteger>(
    _ cbor: CBOR, _ type: T.Type, _ codingPath: @autoclosure () -> [any CodingKey]
) throws -> T {
    let signed: Int64
    switch cbor {
    case .unsignedInt(let value):
        guard let fitted = Int64(exactly: value) else { throw outOfRange(type, codingPath()) }
        signed = fitted
    case .negativeInt(let argument):
        guard let fitted = Int64(exactly: argument) else { throw outOfRange(type, codingPath()) }
        signed = -1 - fitted
    default:
        throw typeMismatch(type, cbor, codingPath())
    }
    guard let result = T(exactly: signed) else { throw outOfRange(type, codingPath()) }
    return result
}

@inline(__always)
private func unboxUnsigned<T: FixedWidthInteger & UnsignedInteger>(
    _ cbor: CBOR, _ type: T.Type, _ codingPath: @autoclosure () -> [any CodingKey]
) throws -> T {
    guard case .unsignedInt(let value) = cbor else { throw typeMismatch(type, cbor, codingPath()) }
    guard let result = T(exactly: value) else { throw outOfRange(type, codingPath()) }
    return result
}

// MARK: - Keyed container

private struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let map: [CBOR: CBOR]
    let decoder: _CBORDecoder

    var codingPath: [any CodingKey] { decoder.codingPath }

    var allKeys: [Key] {
        map.keys.compactMap { key in
            switch key {
            case .textString(let string): return Key(stringValue: string)
            case .unsignedInt, .negativeInt: return key.intValue.flatMap(Key.init(intValue:))
            default: return nil
            }
        }
    }

    /// The value stored under `key`: by its text form, which is what the encoder
    /// writes, or failing that by its integer form, the way COSE and CTAP2 key
    /// their maps. Keys without an `intValue` never pay for the second lookup.
    private func value(for key: Key) -> CBOR? {
        if let value = map[.textString(key.stringValue)] { return value }
        guard let integer = key.intValue else { return nil }
        return map[CBOR(integerLiteral: Int64(integer))]
    }

    private func find(_ key: Key) throws -> CBOR {
        guard let value = value(for: key) else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "No value associated with key \(key.stringValue)."
            ))
        }
        return value
    }

    func contains(_ key: Key) -> Bool {
        value(for: key) != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        try find(key).isNull
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try unboxBool(find(key), codingPath + [key]) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try unboxString(find(key), codingPath + [key]) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try unboxDouble(find(key), codingPath + [key]) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try unboxFloat(find(key), codingPath + [key]) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try unboxSigned(find(key), type, codingPath + [key]) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try unboxSigned(find(key), type, codingPath + [key]) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try unboxSigned(find(key), type, codingPath + [key]) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try unboxSigned(find(key), type, codingPath + [key]) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try unboxSigned(find(key), type, codingPath + [key]) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try unboxUnsigned(find(key), type, codingPath + [key]) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try unboxUnsigned(find(key), type, codingPath + [key]) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try unboxUnsigned(find(key), type, codingPath + [key]) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try unboxUnsigned(find(key), type, codingPath + [key]) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try unboxUnsigned(find(key), type, codingPath + [key]) }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try decoder.child(find(key), at: .key(key)).unbox(as: type)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type, forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        try decoder.child(find(key), at: .key(key)).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        try decoder.child(find(key), at: .key(key)).unkeyedContainer()
    }

    func superDecoder() throws -> any Decoder {
        decoder.child(map[.textString("super")] ?? .null, at: .key(PathKey.super))
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        decoder.child(try find(key), at: .key(key))
    }
}

// MARK: - Unkeyed container

private final class UnkeyedContainer: UnkeyedDecodingContainer {
    let array: [CBOR]
    let decoder: _CBORDecoder
    var currentIndex = 0

    init(array: [CBOR], decoder: _CBORDecoder) {
        self.array = array
        self.decoder = decoder
    }

    var codingPath: [any CodingKey] { decoder.codingPath }
    var count: Int? { array.count }
    var isAtEnd: Bool { currentIndex >= array.count }

    /// The coding path of the element at `index`, for errors.
    private func path(at index: Int) -> [any CodingKey] {
        codingPath + [PathKey(index: index)]
    }

    /// Take the next element. Afterwards it sits at `currentIndex - 1`.
    private func next(_ type: Any.Type) throws -> CBOR {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(
                codingPath: path(at: currentIndex),
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

    // `path(at: currentIndex - 1)` is an autoclosure, evaluated only on failure and
    // so after `next` has advanced past the element it names.
    func decode(_ type: Bool.Type) throws -> Bool { try unboxBool(next(type), path(at: currentIndex - 1)) }
    func decode(_ type: String.Type) throws -> String { try unboxString(next(type), path(at: currentIndex - 1)) }
    func decode(_ type: Double.Type) throws -> Double { try unboxDouble(next(type), path(at: currentIndex - 1)) }
    func decode(_ type: Float.Type) throws -> Float { try unboxFloat(next(type), path(at: currentIndex - 1)) }
    func decode(_ type: Int.Type) throws -> Int { try unboxSigned(next(type), type, path(at: currentIndex - 1)) }
    func decode(_ type: Int8.Type) throws -> Int8 { try unboxSigned(next(type), type, path(at: currentIndex - 1)) }
    func decode(_ type: Int16.Type) throws -> Int16 { try unboxSigned(next(type), type, path(at: currentIndex - 1)) }
    func decode(_ type: Int32.Type) throws -> Int32 { try unboxSigned(next(type), type, path(at: currentIndex - 1)) }
    func decode(_ type: Int64.Type) throws -> Int64 { try unboxSigned(next(type), type, path(at: currentIndex - 1)) }
    func decode(_ type: UInt.Type) throws -> UInt { try unboxUnsigned(next(type), type, path(at: currentIndex - 1)) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try unboxUnsigned(next(type), type, path(at: currentIndex - 1)) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try unboxUnsigned(next(type), type, path(at: currentIndex - 1)) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try unboxUnsigned(next(type), type, path(at: currentIndex - 1)) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try unboxUnsigned(next(type), type, path(at: currentIndex - 1)) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let value = try next(type)
        return try decoder.child(value, at: .index(currentIndex - 1)).unbox(as: type)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let value = try next(type)
        return try decoder.child(value, at: .index(currentIndex - 1)).container(keyedBy: type)
    }

    func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        let value = try next([Any].self)
        return try decoder.child(value, at: .index(currentIndex - 1)).unkeyedContainer()
    }

    func superDecoder() throws -> any Decoder {
        let value = try next((any Decoder).self)
        return decoder.child(value, at: .index(currentIndex - 1))
    }
}

// MARK: - Single-value container

private struct SingleValueContainer: SingleValueDecodingContainer {
    let decoder: _CBORDecoder

    var cbor: CBOR { decoder.cbor }
    var codingPath: [any CodingKey] { decoder.codingPath }

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
        // The value and its path are this decoder's own, so it decodes `T` itself
        // rather than wrapping a copy of itself in a new decoder.
        try decoder.unbox(as: type)
    }
}
