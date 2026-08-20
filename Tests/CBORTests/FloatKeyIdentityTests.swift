import Testing
import CBOR

// A map with two NaN keys of the same width and payload. Under IEEE semantics
// NaN != NaN, so a `[CBOR: CBOR]` would keep both as distinct entries — and
// because they encode to identical bytes, the deterministic key sort has no
// total order to work with and the output byte order becomes unstable.
//
// Found by fuzzing (swift-fuzz, CBORRoundTrip target); the 22-byte reproducer
// was `bf fb ffffffffffffff2c 21 fb ffffffffffffff2c 04 ff`.
private let twoNaNKeys: [UInt8] = [
    0xbf,                                                  // indefinite-length map
    0xfb, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x2c,  // key 1: double NaN
    0x21,                                                  // value 1: -2
    0xfb, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x2c,  // key 2: the same NaN
    0x04,                                                  // value 2: 4
    0xff,                                                  // break
]

@Suite("Float key identity")
struct FloatKeyIdentityTests {
    @Test("NaN values of the same bit pattern are the same CBOR value")
    func nanEqualsItself() {
        // IEEE says no; CBOR's data model says yes, because the two are
        // indistinguishable once encoded.
        #expect(CBOR.double(.nan) == CBOR.double(.nan))
        #expect(CBOR.float(.nan) == CBOR.float(.nan))
        #expect(CBOR.half(.nan) == CBOR.half(.nan))
    }

    @Test("A NaN key does not multiply inside a map")
    func nanKeyCollapses() {
        var map: [CBOR: CBOR] = [:]
        map[.double(.nan)] = 1
        map[.double(.nan)] = 2
        #expect(map.count == 1)
        #expect(map[.double(.nan)] == 2)
    }

    @Test("Decoding a map with a repeated NaN key yields one entry")
    func decodeCollapsesRepeatedNaNKey() throws {
        let value = try CBOR.decode(twoNaNKeys)
        guard case .map(let entries) = value else {
            Issue.record("expected a map, got \(value)")
            return
        }
        #expect(entries.count == 1)
    }

    @Test("Encoding is a fixed point for maps with NaN keys", .serialized)
    func encodingIsStable() throws {
        // Repeated because the instability came from `Dictionary` iteration
        // order, which Swift seeds per process — a single pass would have
        // caught the original bug only about 40% of the time. This runs in one
        // process, so it relies on the collapse above rather than on luck, but
        // the repetition guards against a partial fix.
        let first = try CBOR.decode(twoNaNKeys).encode()
        for _ in 0..<100 {
            let again = try CBOR.decode(twoNaNKeys).encode()
            #expect(again == first)
        }
    }

    @Test("Distinct NaN payloads stay distinct")
    func distinctPayloadsAreDistinctKeys() {
        // Different bit patterns encode differently, so they are genuinely
        // different keys and the sort still has a total order.
        let a = CBOR.double(Double(bitPattern: 0x7ff8_0000_0000_0001))
        let b = CBOR.double(Double(bitPattern: 0x7ff8_0000_0000_0002))
        #expect(a != b)
        #expect(a.encode() != b.encode())
        var map: [CBOR: CBOR] = [:]
        map[a] = 1
        map[b] = 2
        #expect(map.count == 2)
    }

    @Test("Positive and negative zero are different keys")
    func signedZerosAreDistinct() {
        // They encode differently (0xfb 0000… vs 0xfb 8000…), so treating them
        // as one key would reintroduce exactly the same ambiguity.
        #expect(CBOR.double(0.0) != CBOR.double(-0.0))
        #expect(CBOR.double(0.0).encode() != CBOR.double(-0.0).encode())
    }

    @Test("Hashable contract: equal values hash equally")
    func hashableContract() {
        // `==` is hand-written but `hash(into:)` is synthesized, so this pairing
        // is load-bearing: it holds only because the standard library hashes a
        // float as a pure function of its bit pattern. If that ever changed,
        // equal CBOR values could hash differently and maps would silently lose
        // entries — so assert it rather than assume it.
        let payload: UInt64 = 0x7ff8_0000_0000_0001
        let a = CBOR.double(Double(bitPattern: payload))
        let b = CBOR.double(Double(bitPattern: payload))
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)

        #expect(CBOR.double(.nan).hashValue == CBOR.double(.nan).hashValue)
        #expect(CBOR.float(.nan).hashValue == CBOR.float(.nan).hashValue)
        #expect(CBOR.half(.nan).hashValue == CBOR.half(.nan).hashValue)
    }

    @Test("Equal floats of the same width remain equal")
    func ordinaryFloatsUnaffected() {
        #expect(CBOR.double(1.5) == CBOR.double(1.5))
        #expect(CBOR.double(1.5) != CBOR.double(2.5))
        // Different widths are different CBOR items even at the same value.
        #expect(CBOR.double(1.5) != CBOR.float(1.5))
    }
}
