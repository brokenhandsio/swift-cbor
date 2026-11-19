/// An error thrown while decoding CBOR.
///
/// Every case carries `offset`: where in the input the problem is, counted in
/// bytes from 0. It is the position of the head of the data item that could not be
/// decoded, or of the string chunk for a malformed indefinite-length string. When
/// the input ends where an item should begin, the offset is the input's length.
///
/// Offsets count from the start of the bytes passed to `decode`: for an
/// `ArraySlice`, from its `startIndex`, not from the start of the underlying array.
@nonexhaustive
public enum CBORError: Error, Hashable, Sendable {
    /// The input ended before the data item at `offset` could be read completely.
    case unexpectedEnd(offset: Int)

    /// A head byte used a reserved additional-information value (28, 29 or 30), or a
    /// simple value below 32 was written in its two-byte form (additional
    /// information 24).
    case reservedAdditionalInfo(UInt8, offset: Int)

    /// An indefinite-length encoding appeared where it is not permitted: on an
    /// integer or tag, as a string chunk that is not a definite string of the same
    /// type, or as a `break` that ends a map between a key and its value.
    case invalidIndefiniteLength(offset: Int)

    /// A `break` stop code (0xFF) appeared outside of an indefinite-length item.
    case unexpectedBreak(offset: Int)

    /// A text string did not contain valid UTF-8.
    case invalidUTF8(offset: Int)

    /// The item at `offset` is nested deeper than `limit`, the effective
    /// ``CBORDecodingOptions/maximumDepth``.
    case maxDepthExceeded(limit: Int, offset: Int)

    /// A complete top-level item was decoded but `remaining` bytes followed it,
    /// from `offset`, when exactly one item was expected.
    case trailingData(remaining: Int, offset: Int)

    /// A map repeated a key; `offset` is the repeat. Reported unless
    /// ``CBORDecodingOptions/rejectDuplicateMapKeys`` is turned off.
    case duplicateMapKey(offset: Int)

    /// Where in the input the problem is, counted in bytes from 0.
    public var offset: Int {
        switch self {
        case .unexpectedEnd(let offset),
             .reservedAdditionalInfo(_, let offset),
             .invalidIndefiniteLength(let offset),
             .unexpectedBreak(let offset),
             .invalidUTF8(let offset),
             .maxDepthExceeded(_, let offset),
             .trailingData(_, let offset),
             .duplicateMapKey(let offset):
            return offset
        }
    }
}

extension CBORError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unexpectedEnd(let offset):
            "Unexpected end of input reading the item at offset \(offset)"
        case .reservedAdditionalInfo(let value, let offset):
            "Reserved additional information value \(value) at offset \(offset)"
        case .invalidIndefiniteLength(let offset):
            "Invalid indefinite-length encoding at offset \(offset)"
        case .unexpectedBreak(let offset):
            "Unexpected break stop code at offset \(offset)"
        case .invalidUTF8(let offset):
            "Invalid UTF-8 in the text string at offset \(offset)"
        case .maxDepthExceeded(let limit, let offset):
            "Item at offset \(offset) is nested deeper than the limit of \(limit)"
        case .trailingData(let remaining, let offset):
            "\(remaining) unexpected byte\(remaining == 1 ? "" : "s") after the item, from offset \(offset)"
        case .duplicateMapKey(let offset):
            "Duplicate map key at offset \(offset)"
        }
    }
}
