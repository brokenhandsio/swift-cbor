/// A CBOR tag (major type 6) that annotates the enclosed data item with
/// additional semantics, as registered in the IANA CBOR Tags registry.
public struct CBORTag: RawRepresentable, Sendable, Hashable {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    /// Create a tag from its numeric value.
    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

extension CBORTag: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: UInt64) {
        self.rawValue = value
    }
}

extension CBORTag {
    /// Tag 0 — standard date/time string (RFC 3339).
    public static let standardDateTimeString = CBORTag(0)
    /// Tag 1 — epoch-based date/time (numeric seconds since 1970-01-01T00:00Z).
    public static let epochDateTime = CBORTag(1)
    /// Tag 2 — unsigned bignum (big-endian byte string).
    public static let positiveBignum = CBORTag(2)
    /// Tag 3 — negative bignum (big-endian byte string).
    public static let negativeBignum = CBORTag(3)
    /// Tag 4 — decimal fraction.
    public static let decimalFraction = CBORTag(4)
    /// Tag 5 — bigfloat.
    public static let bigfloat = CBORTag(5)
    /// Tag 21 — expected later conversion to base64url.
    public static let expectedBase64URL = CBORTag(21)
    /// Tag 22 — expected later conversion to base64.
    public static let expectedBase64 = CBORTag(22)
    /// Tag 23 — expected later conversion to base16.
    public static let expectedBase16 = CBORTag(23)
    /// Tag 24 — encoded CBOR data item (a byte string containing CBOR).
    public static let encodedCBORData = CBORTag(24)
    /// Tag 32 — URI text string.
    public static let uri = CBORTag(32)
    /// Tag 33 — base64url text string.
    public static let base64URL = CBORTag(33)
    /// Tag 34 — base64 text string.
    public static let base64 = CBORTag(34)
    /// Tag 36 — MIME message.
    public static let mimeMessage = CBORTag(36)
    /// Tag 55799 — self-described CBOR.
    public static let selfDescribedCBOR = CBORTag(55799)
}
