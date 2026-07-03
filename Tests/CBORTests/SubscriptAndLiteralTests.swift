import Testing
import CBOR

@Suite("Literals and accessors")
struct SubscriptAndLiteralTests {
    @Test("integer literals map to the right case")
    func integerLiterals() {
        #expect((0 as CBOR) == .unsignedInt(0))
        #expect((24 as CBOR) == .unsignedInt(24))
        #expect((-1 as CBOR) == .negativeInt(0))
        #expect((-10 as CBOR) == .negativeInt(9))
        #expect((-100 as CBOR) == .negativeInt(99))
    }

    @Test("string, bool, nil, array and dictionary literals")
    func otherLiterals() {
        #expect(("hi" as CBOR) == .textString("hi"))
        #expect((true as CBOR) == .bool(true))
        #expect((nil as CBOR) == .null)
        #expect(([1, 2] as CBOR) == .array([.unsignedInt(1), .unsignedInt(2)]))
        #expect((["a": 1] as CBOR) == .map([.textString("a"): .unsignedInt(1)]))
    }

    @Test("map subscript by CBOR key and by string")
    func mapSubscript() {
        let map: CBOR = ["a": 1, .unsignedInt(2): "b"]
        #expect(map["a"] == .unsignedInt(1))
        #expect(map[.textString("a")] == .unsignedInt(1))
        #expect(map[.unsignedInt(2)] == .textString("b"))
        #expect(map["missing"] == nil)
    }

    @Test("array subscript by unsigned index")
    func arraySubscript() {
        let array: CBOR = [10, 20, 30]
        #expect(array[.unsignedInt(0)] == .unsignedInt(10))
        #expect(array[.unsignedInt(2)] == .unsignedInt(30))
        #expect(array[.unsignedInt(3)] == nil)
    }

    @Test("negative-integer keys (COSE style)")
    func negativeKeys() {
        // COSE keys: -1 is stored as .negativeInt(0), -2 as .negativeInt(1).
        let map: CBOR = [.negativeInt(0): 1, .negativeInt(1): 2]
        #expect(map[.negativeInt(0)] == .unsignedInt(1))
        #expect(map[.negativeInt(1)] == .unsignedInt(2))
    }

    @Test("typed accessors")
    func accessors() {
        #expect((42 as CBOR).int == 42)
        #expect((-7 as CBOR).int == -7)
        #expect(CBOR.unsignedInt(42).uint64 == 42)
        #expect(CBOR.byteString([1, 2]).bytes == [1, 2])
        #expect(CBOR.textString("x").string == "x")
        #expect(CBOR.bool(true).boolValue == true)
        #expect(CBOR.double(1.5).doubleValue == 1.5)
        #expect(CBOR.half(1.5).doubleValue == 1.5)
        #expect(CBOR.null.isNull)
        #expect(CBOR.textString("x").int == nil)
    }
}
