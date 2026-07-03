//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-cbor open source project
//
// Licensed under the MIT license.
//
//===----------------------------------------------------------------------===//

// Literal conformances let CBOR values be written naturally in source and tests,
// e.g. `let item: CBOR = ["a": 1, "b": [2, 3]]`.

extension CBOR: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension CBOR: ExpressibleByIntegerLiteral {
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
    public init(stringLiteral value: String) {
        self = .textString(value)
    }
}

extension CBOR: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension CBOR: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension CBOR: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: CBOR...) {
        self = .array(elements)
    }
}

extension CBOR: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (CBOR, CBOR)...) {
        var map: [CBOR: CBOR] = .init(minimumCapacity: elements.count)
        for (key, value) in elements {
            map[key] = value
        }
        self = .map(map)
    }
}
