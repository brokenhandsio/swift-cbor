//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-cbor open source project
//
// Licensed under the MIT license.
//
//===----------------------------------------------------------------------===//

/// A type that can convert itself directly to a ``CBOR`` value.
///
/// This is a lightweight, native alternative to Swift's `Encodable` for types that
/// want full control over their CBOR representation. For general Swift value trees,
/// prefer ``CBOREncoder``.
public protocol CBOREncodable {
    /// This value expressed as a CBOR data item.
    func toCBOR() -> CBOR
}

/// A type that can initialize itself from a ``CBOR`` value.
public protocol CBORDecodable {
    /// Create a value from a decoded CBOR data item, throwing on a mismatch.
    init(cbor: CBOR) throws
}

/// A type that is both ``CBOREncodable`` and ``CBORDecodable``.
public typealias CBORConvertible = CBOREncodable & CBORDecodable
