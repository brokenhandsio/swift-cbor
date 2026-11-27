import Testing
import CBOR

private struct NestedArrayNode: Decodable {
    init(from decoder: any Decoder) throws {
        var list = try decoder.unkeyedContainer()
        if !list.isAtEnd { _ = try list.decode(Self.self) }
    }
}

private struct NestedStruct: Decodable {
    let child: [NestedStruct]
}

private struct SameValueLoop: Decodable {
    init(from decoder: any Decoder) throws {
        let single = try decoder.singleValueContainer()
        _ = try single.decode(Self.self)
    }
}

@Suite("Codable recursion limit")
struct CodableDepthTests {
    @Test("the limit counts generic Decodable calls, not CBOR bytes or array elements")
    func exactLimit() throws {
        let nested: [UInt8] = [0x81, 0x80]
        #expect(throws: DecodingError.self) {
            try CBORDecoder(maximumCodableDepth: 1).decode(NestedArrayNode.self, from: nested)
        }
        _ = try CBORDecoder(maximumCodableDepth: 2).decode(NestedArrayNode.self, from: nested)

        let wide = CBOR.array((0..<1_000).map { .unsignedInt(UInt64($0)) }).encode()
        // Every element is decoded at the same depth; breadth does not spend
        // the nesting budget.
        #expect(try CBORDecoder(maximumCodableDepth: 2).decode([Int].self, from: wide).count == 1_000)

        let deep = Array(repeating: UInt8(0x81), count: 129) + [0x80]
        #expect(throws: DecodingError.self) {
            try CBORDecoder().decode(NestedArrayNode.self, from: deep)
        }
    }

    @Test("recursive structs fail before exhausting a worker stack")
    func recursiveStruct() throws {
        let nested: [UInt8] = [0xa1, 0x65, 0x63, 0x68, 0x69, 0x6c, 0x64, 0x81]
        let leaf: [UInt8] = [0xa1, 0x65, 0x63, 0x68, 0x69, 0x6c, 0x64, 0x80]
        let bytes = Array(repeating: nested, count: 100).flatMap { $0 } + leaf

        // Parsing this CBOR tree is safe; recursively decoding its Swift model
        // needs a separate stack budget.
        _ = try CBOR.decode(bytes)
        #expect(throws: DecodingError.self) {
            try CBORDecoder().decode(NestedStruct.self, from: bytes)
        }
        _ = try CBORDecoder(maximumCodableDepth: 256).decode(NestedStruct.self, from: bytes)
    }

    @Test("a custom type cannot recurse forever on the same decoder")
    func sameValueRecursion() {
        #expect(throws: DecodingError.self) {
            try CBORDecoder(maximumCodableDepth: 16).decode(SameValueLoop.self, from: [0x00])
        }
    }
}
