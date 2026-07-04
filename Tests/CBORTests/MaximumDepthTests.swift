import Testing
import CBOR

// `depth` nested definite arrays wrapping a leaf `0x00` (leaf sits at that depth).
private func nestedArrays(_ depth: Int) -> [UInt8] {
    [UInt8](repeating: 0x81, count: depth) + [0x00]
}

// `depth` nested tags wrapping a leaf.
private func nestedTags(_ depth: Int) -> [UInt8] {
    [UInt8](repeating: 0xc0, count: depth) + [0x00]
}

// `depth` nested single-entry maps ({0: {0: ... 0}}); the innermost value is the leaf.
private func nestedMaps(_ depth: Int) -> [UInt8] {
    var bytes: [UInt8] = []
    for _ in 0..<depth { bytes += [0xa1, 0x00] }
    bytes.append(0x00)
    return bytes
}

@Suite("Maximum depth")
struct MaximumDepthTests {
    @Test("a value nested at exactly the limit decodes")
    func atLimit() {
        let options = CBOROptions(maximumDepth: 16)
        for input in [nestedArrays(16), nestedTags(16), nestedMaps(16)] {
            #expect(throws: Never.self) {
                _ = try CBOR.decode(input, options: options)
            }
        }
    }

    @Test("one level past the limit throws maxDepthExceeded")
    func pastLimit() {
        let options = CBOROptions(maximumDepth: 16)
        for input in [nestedArrays(17), nestedTags(17), nestedMaps(17)] {
            #expect(throws: CBORError.maxDepthExceeded(16)) {
                try CBOR.decode(input, options: options)
            }
        }
    }

    @Test("maximumDepth 0 allows only unnested top-level items")
    func zeroDepth() {
        let options = CBOROptions(maximumDepth: 0)
        // A primitive and an empty container involve no nesting, so they are allowed.
        #expect(throws: Never.self) { _ = try CBOR.decode([0x00], options: options) }
        #expect(throws: Never.self) { _ = try CBOR.decode([0x80], options: options) } // []
        #expect(throws: Never.self) { _ = try CBOR.decode([0xa0], options: options) } // {}
        // Any actual nesting is rejected.
        #expect(throws: CBORError.maxDepthExceeded(0)) {
            try CBOR.decode(nestedArrays(1), options: options)
        }
    }

    @Test("the default limit is 512")
    func defaultLimit() {
        // 513-deep throws; the depth guard fires before any stack pressure builds
        // (the decoder is iterative, so this can never overflow the stack).
        #expect(throws: CBORError.maxDepthExceeded(512)) {
            try CBOR.decode(nestedArrays(513))
        }
    }

    @Test("mixed container types count toward the same depth budget")
    func mixedNesting() {
        // array > tag > map > array … alternating, 20 deep, with limit 16.
        var bytes: [UInt8] = []
        for level in 0..<20 {
            switch level % 3 {
            case 0: bytes.append(0x81)        // array(1)
            case 1: bytes.append(0xc0)        // tag
            default: bytes += [0xa1, 0x00]    // map(1) with key 0
            }
        }
        bytes.append(0x00)
        #expect(throws: CBORError.maxDepthExceeded(16)) {
            try CBOR.decode(bytes, options: CBOROptions(maximumDepth: 16))
        }
    }
}

@Suite("Empty map handling")
struct EmptyMapTests {
    // Guards the WebAuthn "attestation statement must be empty" check
    // (`attestationStatement == .map([:])`).
    @Test("empty maps compare equal to .map([:])")
    func emptyMapEquality() throws {
        #expect(try CBOR.decode([0xa0]) == .map([:]))       // definite empty map
        #expect(try CBOR.decode([0xbf, 0xff]) == .map([:])) // indefinite empty map
        #expect((.map([:]) as CBOR) == ([:] as CBOR))
    }

    @Test("non-empty maps are not equal to .map([:])")
    func nonEmptyMapInequality() throws {
        #expect(try CBOR.decode(bytes(fromHex: "a10001")) != .map([:]))     // {0: 1}
        #expect(try CBOR.decode(bytes(fromHex: "a1616100")) != .map([:]))   // {"a": 0}
    }

    @Test("a non-map value is not equal to .map([:])")
    func nonMapInequality() throws {
        #expect(try CBOR.decode([0x80]) != .map([:])) // [] is not {}
        #expect(try CBOR.decode([0xf6]) != .map([:])) // null is not {}
    }
}
