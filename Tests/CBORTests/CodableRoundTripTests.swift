import Testing
import Foundation
import CBOR

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
}
