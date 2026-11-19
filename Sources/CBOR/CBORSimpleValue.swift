/// A CBOR simple value (major type 7) with no dedicated ``CBOR`` case: 0–19 or
/// 32–255.
///
/// The rest of the range cannot be represented, by design. Simple values 20–23
/// are `false`, `true`, `null` and `undefined`, which ``CBOR`` models as
/// ``CBOR/bool(_:)``, ``CBOR/null`` and ``CBOR/undefined``; holding them here as
/// well would give two different `CBOR` values the same encoding, and a map could
/// then contain the same encoded key twice. 24–31 are reserved and have no
/// well-formed encoding at all (RFC 8949 §3.3). Ruling both out means every
/// `CBORSimpleValue` encodes exactly one way and decodes back to itself.
public struct CBORSimpleValue: RawRepresentable, Sendable, Hashable {
    public let rawValue: UInt8

    /// Create a simple value, or return `nil` for 20–31.
    public init?(rawValue: UInt8) {
        guard Self.isRepresentable(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// Create a simple value from its number, or return `nil` for 20–31.
    public init?(_ rawValue: UInt8) {
        self.init(rawValue: rawValue)
    }

    /// For values the parser has already range-checked.
    init(unchecked rawValue: UInt8) {
        assert(Self.isRepresentable(rawValue))
        self.rawValue = rawValue
    }

    private static func isRepresentable(_ value: UInt8) -> Bool {
        value < 20 || value >= 32
    }
}

extension CBORSimpleValue: ExpressibleByIntegerLiteral {
    /// Create a simple value from a literal, as in `CBOR.simple(16)`.
    ///
    /// A literal is written into source by hand, so 20–31 here is a programming
    /// error rather than bad input, and it traps. Use ``init(_:)`` for a number
    /// that is not known until runtime.
    public init(integerLiteral value: UInt8) {
        precondition(
            Self.isRepresentable(value),
            "simple(\(value)) is not a valid CBOR simple value: 20–23 are .bool, .null and .undefined, and 24–31 are reserved"
        )
        self.rawValue = value
    }
}

extension CBORSimpleValue: CustomStringConvertible {
    public var description: String { String(rawValue) }
}
