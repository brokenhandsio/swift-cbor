import Testing
import CBOR

private var contextKey: CodingUserInfoKey {
    CodingUserInfoKey(rawValue: "CBORTests.context")!
}

private enum MissingContext: Error {
    case value
}

private struct ContextValue: Codable, Equatable {
    let value: Int

    init(value: Int) { self.value = value }

    init(from decoder: any Decoder) throws {
        guard decoder.userInfo[contextKey] as? String == "soto" else {
            throw MissingContext.value
        }
        value = try decoder.singleValueContainer().decode(Int.self)
    }

    func encode(to encoder: any Encoder) throws {
        guard encoder.userInfo[contextKey] as? String == "soto" else {
            throw MissingContext.value
        }
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

private struct NestedValues: Codable, Equatable {
    let keyed: ContextValue
    let array: [ContextValue]
}

private struct DirectNestedContainer: Codable, Equatable {
    let value: ContextValue

    private enum Keys: String, CodingKey { case values }

    init(value: ContextValue) { self.value = value }

    init(from decoder: any Decoder) throws {
        let keyed = try decoder.container(keyedBy: Keys.self)
        var nested = try keyed.nestedUnkeyedContainer(forKey: .values)
        value = try nested.decode(ContextValue.self)
    }

    func encode(to encoder: any Encoder) throws {
        var keyed = encoder.container(keyedBy: Keys.self)
        var nested = keyed.nestedUnkeyedContainer(forKey: .values)
        try nested.encode(value)
    }
}

private struct SuperValue: Codable, Equatable {
    let value: ContextValue

    private enum Keys: String, CodingKey { case parent }

    init(value: ContextValue) { self.value = value }

    init(from decoder: any Decoder) throws {
        let keyed = try decoder.container(keyedBy: Keys.self)
        value = try ContextValue(from: keyed.superDecoder(forKey: .parent))
    }

    func encode(to encoder: any Encoder) throws {
        var keyed = encoder.container(keyedBy: Keys.self)
        try value.encode(to: keyed.superEncoder(forKey: .parent))
    }
}

private struct SingleValueWrapper: Codable, Equatable {
    let value: ContextValue

    init(value: ContextValue) { self.value = value }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(ContextValue.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

@Suite("Codable userInfo")
struct UserInfoTests {
    @Test("root values see configured context, which is not encoded")
    func root() throws {
        var encoder = CBOREncoder()
        encoder.userInfo[contextKey] = "soto"
        let bytes = try encoder.encode(ContextValue(value: 42))
        #expect(bytes == [0x18, 0x2a])

        var decoder = CBORDecoder()
        decoder.userInfo[contextKey] = "soto"
        #expect(try decoder.decode(ContextValue.self, from: bytes) == ContextValue(value: 42))

        #expect(throws: MissingContext.self) {
            try CBOREncoder().encode(ContextValue(value: 42))
        }
        #expect(throws: MissingContext.self) {
            try CBORDecoder().decode(ContextValue.self, from: bytes)
        }
    }

    @Test("context reaches synthesized keyed and unkeyed values")
    func nested() throws {
        let value = NestedValues(
            keyed: ContextValue(value: 1),
            array: [ContextValue(value: 2), ContextValue(value: 3)]
        )
        let bytes = try CBOREncoder(userInfo: [contextKey: "soto"]).encode(value)
        #expect(try CBORDecoder(userInfo: [contextKey: "soto"]).decode(NestedValues.self, from: bytes) == value)
    }

    @Test("context reaches directly nested containers")
    func directNested() throws {
        let value = DirectNestedContainer(value: ContextValue(value: 4))
        let bytes = try CBOREncoder(userInfo: [contextKey: "soto"]).encode(value)
        #expect(try CBORDecoder(userInfo: [contextKey: "soto"]).decode(DirectNestedContainer.self, from: bytes) == value)
    }

    @Test("context reaches super coders")
    func superCoders() throws {
        let value = SuperValue(value: ContextValue(value: 5))
        let bytes = try CBOREncoder(userInfo: [contextKey: "soto"]).encode(value)
        #expect(try CBORDecoder(userInfo: [contextKey: "soto"]).decode(SuperValue.self, from: bytes) == value)
    }

    @Test("context reaches a nested generic single-value coder")
    func singleValue() throws {
        let value = SingleValueWrapper(value: ContextValue(value: 6))
        let bytes = try CBOREncoder(userInfo: [contextKey: "soto"]).encode(value)
        #expect(try CBORDecoder(userInfo: [contextKey: "soto"]).decode(SingleValueWrapper.self, from: bytes) == value)
    }
}
