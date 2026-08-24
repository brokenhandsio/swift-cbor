import CBOR
import Fuzzing

/// A type shaped to reach as much of the `Codable` bridge as one type can.
///
/// Deliberately mirrors `Everything` in the unit tests. The two cannot share a
/// definition — a fuzz target is its own module and cannot import a test
/// target — so this is duplication with a purpose: the unit test pins the
/// behaviour for one hand-written value, and this drives the same containers
/// with whatever the fuzzer invents.
struct Everything: Codable {
    struct Nested: Codable {
        var small: Int8
        var wide: Double
    }

    var flag: Bool
    var text: String
    var int: Int
    var int8: Int8
    var int16: Int16
    var int32: Int32
    var int64: Int64
    var uint: UInt
    var uint8: UInt8
    var uint16: UInt16
    var uint32: UInt32
    var uint64: UInt64
    var float: Float
    var double: Double
    var presentOptional: String?
    var absentOptional: String?
    var nested: Nested
    var numbers: [Int32]
    var nestedArrays: [[UInt8]]
    var records: [Nested]
    var optionals: [String?]
    var lookup: [String: Int16]
}

let fuzzTargets: @Sendable () -> Void = {
    // The `Codable` bridge, which the other targets never touch: they go
    // straight to the parser, so `CBORDecoder` and `CBOREncoder` sat at 0
    // coverage in every fuzzing report while the parser sat at 99%.
    //
    // The oracle is the encode fixed point rather than value equality, for two
    // reasons. Floats make `==` the wrong comparison — a decoded NaN is not
    // equal to itself, and this type has two float fields the fuzzer will
    // certainly fill with them. And comparing bytes tests the encoder as well
    // as the decoder, rather than only asserting the decoder is self-consistent.
    FuzzTarget.bytes("CBORCodable") { bytes in
        // Deterministic, because the fixed point genuinely does not hold
        // without it: map keys are otherwise emitted in `Dictionary` order,
        // which differs between two separately decoded values, so `lookup`
        // alone can legitimately encode two ways. Asserting it unconditionally
        // would report the harness's own assumption as a library bug.
        let options = CBOROptions(deterministic: true)
        let decoder = CBORDecoder(options: options)
        let encoder = CBOREncoder(options: options)

        // Most inputs are not a valid `Everything`; that rejection is a normal
        // thrown error and not interesting.
        guard let value = try? decoder.decode(Everything.self, from: bytes) else { return }

        guard let once = try? encoder.encode(value) else {
            fatalError("a value the decoder produced could not be encoded")
        }
        guard let again = try? decoder.decode(Everything.self, from: once) else {
            fatalError("re-encoding a decoded value produced bytes that no longer decode")
        }
        guard let twice = try? encoder.encode(again), twice == once else {
            fatalError("deterministic Codable encoding is not a fixed point")
        }
    }
}
