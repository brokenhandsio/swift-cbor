import Testing
import CBOR

@Suite("Error offsets")
struct ErrorOffsetTests {
    @Test("an error points at the head of the item that failed", arguments: [
        // A truncated item, nested: the uint16 at offset 2 is missing a byte.
        ("820119", CBORError.unexpectedEnd(offset: 2)),
        // A missing item: the array wants a second element where the input ends.
        ("8201", .unexpectedEnd(offset: 2)),
        // Invalid UTF-8 in a map value.
        ("a1616162ffff", .invalidUTF8(offset: 3)),
        // A reserved additional-information value inside an array.
        ("811c", .reservedAdditionalInfo(28, offset: 1)),
        // A break inside a definite-length array.
        ("8201ff", .unexpectedBreak(offset: 2)),
        // Indefinite length on an integer.
        ("811f", .invalidIndefiniteLength(offset: 1)),
        // A break between an indefinite map's key and its value: the break's offset.
        ("bf01ff", .invalidIndefiniteLength(offset: 2)),
        // Two bytes left over after a complete item, from offset 2.
        ("81000000", .trailingData(remaining: 2, offset: 2)),
    ])
    func itemOffsets(hex: String, error: CBORError) {
        #expect(throws: error) {
            try CBOR.decode(bytes(fromHex: hex))
        }
    }

    @Test("indefinite-length strings report chunk problems at the chunk", arguments: [
        // The chunk at offset 1 promises two bytes and has one.
        ("5f4201", CBORError.unexpectedEnd(offset: 1)),
        // The input ends where the next chunk or the break should be.
        ("5f4101", .unexpectedEnd(offset: 3)),
        // A text chunk inside a byte string.
        ("5f4101616100ff", .invalidIndefiniteLength(offset: 3)),
    ])
    func chunkOffsets(hex: String, error: CBORError) {
        #expect(throws: error) {
            try CBOR.decode(bytes(fromHex: hex))
        }
    }

    @Test("invalid UTF-8 in an indefinite text string points at its chunk", arguments: [
        ("817f61ffff", 2),       // one invalid chunk nested in an array
        ("7f61c361a9ff", 1),     // a valid code point split across chunks
        ("7f616161ffff", 3),     // a valid first chunk, then an invalid one
        ("7f62f09f629891ff", 1), // a four-byte code point split in half
    ])
    func chunkedUTF8(hex: String, offset: Int) {
        #expect(throws: CBORError.invalidUTF8(offset: offset)) {
            try CBOR.decode(bytes(fromHex: hex))
        }
    }

    @Test("chunk offset is relative to an input slice and survives decodeFirst")
    func chunkedUTF8Slice() {
        let padded: [UInt8] = [0xaa, 0xbb] + bytes(fromHex: "7f61c361a9ff")
        #expect(throws: CBORError.invalidUTF8(offset: 1)) {
            try CBOR.decode(padded[2...])
        }
        #expect(throws: CBORError.invalidUTF8(offset: 1)) {
            try CBOR.decodeFirst(padded[2...])
        }
        #expect(throws: CBORError.invalidUTF8(offset: 1)) {
            try CBORDecoder().decode(String.self, from: padded[2...])
        }
    }

    @Test("offsets count from the start of a slice, not of its array")
    func sliceRelative() {
        let padded: [UInt8] = [0xaa, 0xbb] + bytes(fromHex: "8262ffff")
        #expect(throws: CBORError.invalidUTF8(offset: 1)) {
            try CBOR.decode(padded[2...])
        }
        #expect(throws: CBORError.invalidUTF8(offset: 1)) {
            try CBOR.decodeFirst(padded[2...])
        }
    }

    @Test("offset reads the offset of every case", arguments: [
        (CBORError.unexpectedEnd(offset: 1), 1),
        (.reservedAdditionalInfo(28, offset: 2), 2),
        (.invalidIndefiniteLength(offset: 3), 3),
        (.unexpectedBreak(offset: 4), 4),
        (.invalidUTF8(offset: 5), 5),
        (.maxDepthExceeded(limit: 16, offset: 6), 6),
        (.trailingData(remaining: 1, offset: 7), 7),
        (.duplicateMapKey(offset: 8), 8),
    ])
    func offsetProperty(error: CBORError, offset: Int) {
        #expect(error.offset == offset)
    }

    @Test("the README example prints what the README says")
    func readmeExample() {
        let error = #expect(throws: CBORError.self) {
            try CBOR.decode([0x82, 0x01, 0x62, 0xff, 0xff])
        }
        #expect(error.map(String.init(describing:)) == "Invalid UTF-8 in the text string at offset 2")
        #expect(error?.offset == 2)
    }

    @Test("descriptions name the offset")
    func descriptions() {
        #expect(CBORError.duplicateMapKey(offset: 4).description == "Duplicate map key at offset 4")
        #expect(CBORError.invalidUTF8(offset: 3).description == "Invalid UTF-8 in the text string at offset 3")
        #expect(
            CBORError.maxDepthExceeded(limit: 16, offset: 17).description
                == "Item at offset 17 is nested deeper than the limit of 16"
        )
        #expect(
            CBORError.trailingData(remaining: 1, offset: 1).description
                == "1 unexpected byte after the item, from offset 1"
        )
        #expect(
            CBORError.trailingData(remaining: 2, offset: 1).description
                == "2 unexpected bytes after the item, from offset 1"
        )
    }
}
