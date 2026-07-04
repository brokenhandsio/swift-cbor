import Testing
import CBOR
#if FoundationSupport
import Foundation
#endif

private struct Point: Codable, Equatable {
    var x: Int
    var y: Int
}

private struct Person: Codable, Equatable {
    var name: String
    var age: Int
    var email: String?
    var scores: [Double]
    var home: Point
    var active: Bool
}

private enum Suit: String, Codable, Equatable {
    case hearts, spades, clubs, diamonds
}

@Suite("Codable bridge")
struct CodableRoundTripTests {
    private func roundTrip<T: Codable & Equatable>(_ value: T) throws {
        let bytes = try CBOREncoder().encode(value)
        let decoded = try CBORDecoder().decode(T.self, from: bytes)
        #expect(decoded == value)
    }

    @Test("simple struct")
    func point() throws {
        try roundTrip(Point(x: 3, y: -4))
    }

    @Test("nested struct with optionals, arrays and enums")
    func person() throws {
        try roundTrip(Person(
            name: "Ada",
            age: 36,
            email: nil,
            scores: [1.5, 2.25, -3.0],
            home: Point(x: 0, y: 0),
            active: true
        ))
        try roundTrip(Person(
            name: "Bo",
            age: 1,
            email: "bo@example.com",
            scores: [],
            home: Point(x: -1, y: 2),
            active: false
        ))
    }

    @Test("top-level containers")
    func containers() throws {
        try roundTrip([1, 2, 3])
        try roundTrip(["a": 1, "b": 2])
        try roundTrip([Point(x: 1, y: 2), Point(x: 3, y: 4)])
    }

    @Test("top-level single values")
    func singleValues() throws {
        try roundTrip(42)
        try roundTrip(-7)
        try roundTrip("hello")
        try roundTrip(true)
        try roundTrip(3.14159)
        try roundTrip(Suit.spades)
    }

    @Test("a struct encodes to a CBOR map with deterministic text keys")
    func encodesToMap() throws {
        let bytes = try CBOREncoder().encode(Point(x: 1, y: 2))
        let value = try CBOR.decode(bytes)
        #expect(value == ["x": 1, "y": 2])
        // a2 6178 01 6179 02 — keys "x" (0x6178) and "y" (0x6179) sorted x before y.
        #expect(hexString(bytes) == "a2617801617902")
    }

    // Independent-direction checks: encode against fixed bytes and decode from
    // fixed bytes separately, so a bug shared by both directions can't hide behind
    // a round trip.

    @Test("encoder produces exact bytes")
    func encoderExactBytes() throws {
        #expect(hexString(try CBOREncoder().encode(Point(x: 1, y: 2))) == "a2617801617902")
        #expect(hexString(try CBOREncoder().encode([1, 2, 3])) == "83010203")
        #expect(hexString(try CBOREncoder().encode("IETF")) == "6449455446")
        #expect(hexString(try CBOREncoder().encode(true)) == "f5")
        #expect(hexString(try CBOREncoder().encode(42)) == "182a")
        #expect(hexString(try CBOREncoder().encode(-1)) == "20")
        #expect(hexString(try CBOREncoder().encode(Suit.spades)) == "66737061646573")
    }

    @Test("decoder reads exact bytes")
    func decoderExactBytes() throws {
        #expect(try CBORDecoder().decode(Point.self, from: bytes(fromHex: "a2617801617902")) == Point(x: 1, y: 2))
        #expect(try CBORDecoder().decode([Int].self, from: bytes(fromHex: "83010203")) == [1, 2, 3])
        #expect(try CBORDecoder().decode(String.self, from: bytes(fromHex: "6449455446")) == "IETF")
        #expect(try CBORDecoder().decode(Bool.self, from: bytes(fromHex: "f5")) == true)
        #expect(try CBORDecoder().decode(Int.self, from: bytes(fromHex: "182a")) == 42)
        #expect(try CBORDecoder().decode(Int.self, from: bytes(fromHex: "20")) == -1)
        #expect(try CBORDecoder().decode(Suit.self, from: bytes(fromHex: "66737061646573")) == .spades)
    }

    #if FoundationSupport
    @Test("Data encodes to a CBOR byte string")
    func dataAsByteString() throws {
        struct Blob: Codable, Equatable { var payload: Data }
        let blob = Blob(payload: Data([0x01, 0x02, 0x03]))
        let bytes = try CBOREncoder().encode(blob)
        let value = try CBOR.decode(bytes)
        #expect(value["payload"] == .byteString([0x01, 0x02, 0x03]))

        let decoded = try CBORDecoder().decode(Blob.self, from: bytes)
        #expect(decoded == blob)
    }
    #endif
}
