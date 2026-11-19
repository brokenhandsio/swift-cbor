#if FoundationSupport
import Testing
import CBOR
import Foundation

private struct Event: Codable, Equatable {
    var start: Date
    var times: [Date]
    var end: Date?
}

@Suite("Codable Date")
struct CodableDateTests {
    // MARK: Encoding

    @Test("a whole-second Date encodes as tag 1 with an integer")
    func wholeSecond() throws {
        // RFC 8949 Appendix A: 1(1363896240).
        let date = Date(timeIntervalSince1970: 1_363_896_240)
        #expect(hexString(try CBOREncoder().encode(date)) == "c11a514b67b0")
    }

    @Test("a fractional Date encodes as tag 1 with a double")
    func fractionalSecond() throws {
        // RFC 8949 Appendix A: 1(1363896240.5).
        let date = Date(timeIntervalSince1970: 1_363_896_240.5)
        #expect(hexString(try CBOREncoder().encode(date)) == "c1fb41d452d9ec200000")
    }

    @Test("a Date before 1970 encodes as a negative integer")
    func beforeEpoch() throws {
        #expect(hexString(try CBOREncoder().encode(Date(timeIntervalSince1970: -1))) == "c120")
    }

    @Test("a Date property encodes as tag 1 inside the map")
    func nestedEncoding() throws {
        struct Stamp: Encodable { var at: Date }
        let bytes = try CBOREncoder().encode(Stamp(at: Date(timeIntervalSince1970: 1_363_896_240)))
        #expect(try CBOR.decode(bytes)["at"] == .tagged(.epochDateTime, .unsignedInt(1_363_896_240)))
    }

    // MARK: Round trips

    @Test("whole-second dates round-trip exactly, in properties, arrays and optionals")
    func roundTrip() throws {
        let event = Event(
            start: Date(timeIntervalSince1970: 1_363_896_240),
            times: [.distantPast, Date(timeIntervalSince1970: 0), .distantFuture],
            end: nil
        )
        let decoded = try CBORDecoder().decode(Event.self, from: CBOREncoder().encode(event))
        #expect(decoded == event)
    }

    @Test("fractional dates round-trip to within a microsecond")
    func fractionalRoundTrip() throws {
        // Converting between the 2001 and 1970 epochs rounds the double, so a
        // fraction of a second is not always bit-exact after a round trip.
        let date = Date(timeIntervalSinceReferenceDate: 785_000_000.123_456)
        let decoded = try CBORDecoder().decode(Date.self, from: CBOREncoder().encode(date))
        #expect(abs(decoded.timeIntervalSince(date)) < 1e-6)
    }

    // MARK: Decoding

    @Test("tag 1 with any numeric content decodes", arguments: [
        ("c11a514b67b0", 1_363_896_240.0),
        ("c1fb41d452d9ec200000", 1_363_896_240.5),
        ("c1f93c00", 1.0),    // half-precision 1.0
        ("c120", -1.0),
    ])
    func taggedDecoding(hex: String, seconds: Double) throws {
        let date = try CBORDecoder().decode(Date.self, from: bytes(fromHex: hex))
        #expect(date == Date(timeIntervalSince1970: seconds))
    }

    @Test("a bare number decodes as seconds since 1970", arguments: [
        ("1a514b67b0", 1_363_896_240.0),
        ("fb41d452d9ec200000", 1_363_896_240.5),
        ("20", -1.0),
    ])
    func bareDecoding(hex: String, seconds: Double) throws {
        let date = try CBORDecoder().decode(Date.self, from: bytes(fromHex: hex))
        #expect(date == Date(timeIntervalSince1970: seconds))
    }

    @Test("anything else is a type mismatch", arguments: [
        "c074323031332d30332d32315432303a30343a30305a", // 0("2013-03-21T20:04:00Z")
        "c16161",                                       // 1("a")
        "6161",                                         // "a"
        "f6",                                           // null
        "c21a514b67b0",                                 // a number under a different tag
    ])
    func typeMismatch(hex: String) {
        let error = #expect(throws: DecodingError.self) {
            try CBORDecoder().decode(Date.self, from: bytes(fromHex: hex))
        }
        guard case .typeMismatch(let type, _)? = error else {
            Issue.record("expected a type mismatch, got \(String(describing: error))")
            return
        }
        #expect(type is Date.Type)
    }

    @Test("a type mismatch reports the property's coding path")
    func mismatchPath() {
        struct Stamp: Decodable { var at: Date }
        let error = #expect(throws: DecodingError.self) {
            try CBORDecoder().decode(Stamp.self, from: bytes(fromHex: "a16261746161")) // {"at": "a"}
        }
        guard case .typeMismatch(_, let context)? = error else {
            Issue.record("expected a type mismatch, got \(String(describing: error))")
            return
        }
        #expect(context.codingPath.map(\.stringValue) == ["at"])
    }
}
#endif
