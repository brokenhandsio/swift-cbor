import Testing
import CBOR

/// `CBORSimpleValue` exists so that `.simple` can only hold values with exactly
/// one encoding of their own. Before it, `.simple(20)` encoded as `false` and
/// `.simple(24)` encoded as bytes this library's own decoder rejects.
@Suite("Simple values")
struct SimpleValueTests {
    @Test("only 0–19 and 32–255 are representable")
    func representableRange() {
        for value in UInt8.min...UInt8.max {
            let expected = value < 20 || value >= 32
            #expect((CBORSimpleValue(value) != nil) == expected, "simple(\(value))")
            #expect((CBORSimpleValue(rawValue: value) != nil) == expected, "simple(\(value))")
        }
    }

    @Test("every representable value has its own encoding and round-trips")
    func roundTripsExhaustively() throws {
        for raw in UInt8.min...UInt8.max {
            guard let simple = CBORSimpleValue(raw) else { continue }
            let value = CBOR.simple(simple)
            let bytes = value.encode()
            #expect(bytes == (raw < 20 ? [0xe0 | raw] : [0xf8, raw]), "simple(\(raw))")
            #expect(try CBOR.decode(bytes) == value, "simple(\(raw))")
        }
    }

    @Test("20–23 decode as their dedicated cases, never .simple")
    func dedicatedCases() throws {
        #expect(try CBOR.decode([0xf4]) == .bool(false))
        #expect(try CBOR.decode([0xf5]) == .bool(true))
        #expect(try CBOR.decode([0xf6]) == .null)
        #expect(try CBOR.decode([0xf7]) == .undefined)
    }

    @Test("the two-byte form of 0–31 is rejected", arguments: UInt8(0)...31)
    func twoByteFormRejected(_ value: UInt8) {
        #expect(throws: CBORError.reservedAdditionalInfo(24)) {
            try CBOR.decode([0xf8, value])
        }
    }

    @Test("prints as its number")
    func description() {
        #expect("\(CBOR.simple(16))" == "simple(16)")
    }

    #if os(macOS) || os(Linux)
    // Exit tests are unavailable on iOS and the other embedded platforms.
    @Test("a literal 20–31 traps")
    func invalidLiteralTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = CBOR.simple(24)
        }
    }
    #endif
}
