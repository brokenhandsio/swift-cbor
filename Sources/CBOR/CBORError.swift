/// An error thrown while decoding or encoding CBOR.
@nonexhaustive
public enum CBORError: Error, Hashable, Sendable {
    /// The input ended before a complete data item could be read.
    case unexpectedEnd

    /// A byte used a reserved additional-information value (28, 29 or 30).
    case reservedAdditionalInfo(UInt8)

    /// An indefinite-length encoding appeared where it is not permitted (for
    /// example an indefinite-length string whose chunks are not definite strings).
    case invalidIndefiniteLength

    /// A `break` stop code (0xFF) appeared outside of an indefinite-length item.
    case unexpectedBreak

    /// A text string did not contain valid UTF-8.
    case invalidUTF8

    /// Decoding exceeded ``CBOROptions/maximumDepth``. The associated value is the
    /// limit that was hit.
    case maxDepthExceeded(Int)

    /// A complete top-level item was decoded but extra bytes remained, when exactly
    /// one item was expected. The associated value is the number of unconsumed bytes.
    case trailingData(remaining: Int)

    /// A map contained a duplicate key. Only reported when
    /// ``CBOROptions/rejectDuplicateMapKeys`` is enabled.
    case duplicateMapKey
}
