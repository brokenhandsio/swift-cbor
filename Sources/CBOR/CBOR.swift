/// A decoded CBOR (Concise Binary Object Representation, [RFC 8949]) data item.
///
/// `CBOR` is the in-memory value model produced when decoding bytes and consumed
/// when encoding. Each case corresponds to a CBOR major type or a well-known
/// major-type-7 simple value.
///
/// ## Nesting depth
///
/// `CBOR` is a recursive value type: an array holds `[CBOR]`, whose elements hold
/// more. Parsing, encoding and equality all walk that structure iteratively, and
/// hashing is depth-bounded, so none of them recurse. *Releasing* a value is done
/// by the Swift runtime, which does recurse — roughly 280 bytes of stack per level.
/// That is fine at any depth real data reaches, but a value nested many thousands
/// deep can overflow the stack when it goes out of scope, and the exact limit
/// depends on the stack it is released on: around 30,000 levels on an 8 MB main
/// thread, but only around 1,800 on the 512 KB threads Swift concurrency uses.
///
/// Decoding cannot produce such a value: it is capped at
/// ``CBOROptions/maximumSupportedDepth``, and both ``CBOR/decode(_:options:)-(Span<UInt8>,_)``
/// and ``CBORDecoder`` go through that cap. Nothing else in this library builds
/// nested values either, so the limit is only reachable by writing a loop that
/// deliberately nests one — which no real code does.
///
/// If you convert *untrusted* data from another format into `CBOR` yourself, bound
/// your own recursion the way the decoder does; this type cannot do it for you,
/// because a public enum case can be constructed directly and Swift offers no way
/// to intercept that.
///
/// [RFC 8949]: https://www.rfc-editor.org/rfc/rfc8949.html
@nonexhaustive
public enum CBOR: Sendable, Hashable {
    /// An unsigned integer, `0 ... UInt64.max` (major type 0).
    case unsignedInt(UInt64)

    /// A negative integer (major type 1).
    ///
    /// The associated value `n` is the CBOR-encoded argument; the mathematical
    /// value it represents is `-1 - n`. So `.negativeInt(0)` is `-1` and
    /// `.negativeInt(9)` is `-10`. This representation preserves the full CBOR
    /// negative range down to `-2^64`, which does not fit in `Int64`.
    ///
    /// Use ``int`` for the signed value when it fits in `Int`.
    case negativeInt(UInt64)

    /// A byte string (major type 2).
    case byteString([UInt8])

    /// A UTF-8 text string (major type 3).
    case textString(String)

    /// An array of data items (major type 4).
    case array([CBOR])

    /// A map of key/value pairs (major type 5).
    ///
    /// Modeled as a Swift dictionary: lookups are O(1) and duplicate keys are not
    /// representable. Encoding emits keys in deterministic (RFC 8949 §4.2) order.
    case map([CBOR: CBOR])

    /// A tagged data item (major type 6): a ``CBORTag`` annotating a nested item.
    indirect case tagged(CBORTag, CBOR)

    /// A simple value (major type 7) other than the dedicated cases below.
    case simple(UInt8)

    /// A boolean (major type 7, simple values 20 and 21).
    case bool(Bool)

    /// The `null` value (major type 7, simple value 22).
    case null

    /// The `undefined` value (major type 7, simple value 23).
    case undefined

    /// An IEEE 754 half-precision float (major type 7, additional info 25).
    case half(Float16)

    /// An IEEE 754 single-precision float (major type 7, additional info 26).
    case float(Float)

    /// An IEEE 754 double-precision float (major type 7, additional info 27).
    case double(Double)
}
