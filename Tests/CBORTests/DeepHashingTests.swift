import Testing
import CBOR

@Suite("Deep value hashing")
struct DeepHashingTests {
    private func nestedArrays(_ depth: Int, leaf: CBOR = .unsignedInt(0)) -> CBOR {
        var value = leaf
        for _ in 0..<depth { value = .array([value]) }
        return value
    }

    @Test("A deeply nested map key does not overflow the stack")
    func deepMapKey() {
        // Synthesized hashing recursed once per level and died somewhere
        // between depth 512 and 1000 — close enough to the default
        // maximumDepth of 512 to matter, and reachable from decoded input as
        // soon as a caller raises that limit, because the parser stores keys
        // with `pairs[key] = value`.
        var map: [CBOR: CBOR] = [:]
        map[nestedArrays(1_000)] = 1
        #expect(map.count == 1)
    }

    @Test("A deeply nested value can be decoded and used as a key")
    func decodedDeepKey() throws {
        // The shape that found this: a map whose key is deeply nested, decoded
        // with the depth limit raised.
        var bytes: [UInt8] = [0xbf]                  // indefinite-length map
        bytes += [UInt8](repeating: 0x81, count: 1_000)  // key: 1000 nested arrays
        bytes += [0x00, 0x00, 0xff]                  // leaf, value, break
        let value = try CBOR.decode(bytes, options: CBORDecodingOptions(maximumDepth: .max))
        guard case .map(let entries) = value else {
            Issue.record("expected a map, got \(value)")
            return
        }
        #expect(entries.count == 1)
    }

    @Test("Equal deep values still hash equally")
    func equalDeepValuesHashEqually() {
        // Iterative hashing must still obey the Hashable contract at every depth.
        let a = nestedArrays(1_000)
        let b = nestedArrays(1_000)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Deep differences affect hashes")
    func deepDifferencesHashDifferently() {
        let a = nestedArrays(40, leaf: .unsignedInt(1))
        let b = nestedArrays(40, leaf: .unsignedInt(2))
        #expect(a != b)
        #expect(a.hashValue != b.hashValue)

        var map: [CBOR: CBOR] = [:]
        map[a] = "a"
        map[b] = "b"
        #expect(map.count == 2)
        #expect(map[a] == "a")
        #expect(map[b] == "b")
    }

    @Test("Many keys with the same deep prefix do not share a hash")
    func manyDeepKeys() throws {
        let keys = (0..<256).map { nestedArrays(17, leaf: .unsignedInt(UInt64($0))) }
        #expect(Set(keys.map(\.hashValue)).count == keys.count)

        var map: [CBOR: CBOR] = [:]
        for (index, key) in keys.enumerated() {
            map[key] = .unsignedInt(UInt64(index))
        }
        let decoded = try CBOR.decode(CBOR.map(map).encode())
        #expect(decoded.mapValue?.count == keys.count)
    }

    @Test("Shallow differences still separate, so hashing stays useful")
    func shallowDifferencesSeparate() {
        let a = nestedArrays(4, leaf: .unsignedInt(1))
        let b = nestedArrays(4, leaf: .unsignedInt(2))
        #expect(a.hashValue != b.hashValue)
    }

    @Test("Maps hash independently of iteration order")
    func mapHashingIsCommutative() {
        // The map case combines elements commutatively. Nested values still
        // need to be hashed completely without depending on dictionary order.
        var first: [CBOR: CBOR] = [:]
        for index in 0..<32 { first[.unsignedInt(UInt64(index))] = nestedArrays(40, leaf: .unsignedInt(UInt64(index))) }
        var second: [CBOR: CBOR] = [:]
        for index in (0..<32).reversed() { second[.unsignedInt(UInt64(index))] = nestedArrays(40, leaf: .unsignedInt(UInt64(index))) }
        #expect(CBOR.map(first) == CBOR.map(second))
        #expect(CBOR.map(first).hashValue == CBOR.map(second).hashValue)
    }
}
