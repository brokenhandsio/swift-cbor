// Ergonomic read access to a decoded `CBOR` value: subscripts for maps/arrays and
// typed accessors that return `nil` on a case mismatch.

extension CBOR {
    /// Look up a value by key in a `.map`, or an element by index in an `.array`.
    ///
    /// For arrays the key must be an `.unsignedInt` index that is in bounds.
    /// Returns `nil` for any other receiver, a missing key, or an out-of-range index.
    public subscript(key: CBOR) -> CBOR? {
        switch self {
        case .map(let map):
            return map[key]
        case .array(let array):
            guard case .unsignedInt(let index) = key, index < UInt64(array.count) else {
                return nil
            }
            return array[Int(index)]
        default:
            return nil
        }
    }

    /// Look up a value in a `.map` by a text-string key.
    public subscript(key: String) -> CBOR? {
        self[.textString(key)]
    }
}

extension CBOR {
    /// The signed integer value if this is an integer that fits in `Int`.
    ///
    /// Handles both `.unsignedInt` and `.negativeInt` (applying the `-1 - n`
    /// convention). Returns `nil` for non-integers or values outside `Int`'s range.
    public var int: Int? {
        switch self {
        case .unsignedInt(let value):
            return Int(exactly: value)
        case .negativeInt(let argument):
            guard let signed = Int64(exactly: argument) else { return nil }
            return Int(exactly: -1 - signed)
        default:
            return nil
        }
    }

    /// The value as a `UInt64` if this is an `.unsignedInt`.
    public var uint64: UInt64? {
        guard case .unsignedInt(let value) = self else { return nil }
        return value
    }

    /// The bytes if this is a `.byteString`.
    public var bytes: [UInt8]? {
        guard case .byteString(let bytes) = self else { return nil }
        return bytes
    }

    /// The string if this is a `.textString`.
    public var string: String? {
        guard case .textString(let string) = self else { return nil }
        return string
    }

    /// The elements if this is an `.array`.
    public var arrayValue: [CBOR]? {
        guard case .array(let array) = self else { return nil }
        return array
    }

    /// The entries if this is a `.map`.
    public var mapValue: [CBOR: CBOR]? {
        guard case .map(let map) = self else { return nil }
        return map
    }

    /// The boolean if this is a `.bool`.
    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    /// The floating-point value if this is a `.half`, `.float` or `.double`,
    /// widened to `Double`.
    public var doubleValue: Double? {
        switch self {
        case .half(let value):
            return Double(value)
        case .float(let value):
            return Double(value)
        case .double(let value):
            return value
        default:
            return nil
        }
    }

    /// Whether this is the `.null` value.
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}
