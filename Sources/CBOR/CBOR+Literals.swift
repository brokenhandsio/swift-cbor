// Literal conformances let CBOR values be written naturally in source and tests,
// e.g. `let item: CBOR = ["a": 1, "b": [2, 3]]`.

extension CBOR: ExpressibleByNilLiteral {
    /// `nil` is ``null``.
    @inlinable
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension CBOR: ExpressibleByIntegerLiteral {
    /// An integer literal is ``unsignedInt(_:)`` when it is zero or more, and
    /// ``negativeInt(_:)`` otherwise.
    ///
    /// Literals are limited to the `Int64` range. Use the cases directly for the
    /// rest of CBOR's integer range, which runs from -2⁶⁴ to 2⁶⁴ - 1.
    @inlinable
    public init(integerLiteral value: Int64) {
        if value < 0 {
            // For negative v, the CBOR argument is (-1 - v), which equals the
            // bitwise complement of v reinterpreted as unsigned. This avoids
            // overflow at Int64.min.
            self = .negativeInt(~UInt64(bitPattern: value))
        } else {
            self = .unsignedInt(UInt64(value))
        }
    }
}

extension CBOR: ExpressibleByStringLiteral {
    /// A string literal is a ``textString(_:)``.
    @inlinable
    public init(stringLiteral value: String) {
        self = .textString(value)
    }
}

extension CBOR: ExpressibleByBooleanLiteral {
    /// `true` and `false` are ``bool(_:)``.
    @inlinable
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension CBOR: ExpressibleByFloatLiteral {
    /// A floating-point literal is a ``double(_:)``, so `1.5` encodes in nine
    /// bytes. Use ``half(bitPattern:)`` or ``float(_:)`` for a narrower encoding.
    @inlinable
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension CBOR: ExpressibleByArrayLiteral {
    /// An array literal is an ``array(_:)``.
    @inlinable
    public init(arrayLiteral elements: CBOR...) {
        self = .array(elements)
    }
}

extension CBOR: ExpressibleByDictionaryLiteral {
    /// A dictionary literal is a ``map(_:)``. If a key appears more than once, the
    /// last value wins.
    @inlinable
    public init(dictionaryLiteral elements: (CBOR, CBOR)...) {
        var map: [CBOR: CBOR] = .init(minimumCapacity: elements.count)
        for (key, value) in elements {
            map[key] = value
        }
        self = .map(map)
    }
}
