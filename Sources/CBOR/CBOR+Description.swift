// MARK: - Diagnostic notation

extension CBOR: CustomStringConvertible {
    /// The value in CBOR diagnostic notation (RFC 8949 §8), such as
    /// `[1, "a", h'ff']` or `{1: 2, "at": 1(1363896240)}`.
    ///
    /// - Integers print in decimal, across CBOR's whole range of -2⁶⁴ to 2⁶⁴ - 1.
    /// - Text strings print in double quotes, escaping `"`, `\` and control
    ///   characters as JSON does.
    /// - Byte strings print as `h'…'` in lowercase hex.
    /// - Floats print as the shortest decimal that reads back as the same value,
    ///   always with a decimal point or an exponent (`1.0`, `1e+100`), or as `NaN`,
    ///   `Infinity` or `-Infinity`. NaN payloads are not shown.
    /// - A ``half(bitPattern:)`` ends in the encoding indicator `_1` and a
    ///   ``float(_:)`` in `_2`, so the three float cases, which are different values
    ///   even when they hold the same number, print differently: `1.5_1`, `1.5_2`
    ///   and `1.5`.
    /// - Map entries print in the order they encode, sorted by key, so the same map
    ///   always prints the same way.
    /// - Tags print as `number(item)` and simple values as `simple(number)`.
    ///
    /// Printing walks nested values iteratively, so it cannot overflow the stack.
    public var description: String {
        var out = ""
        var stack: [DescriptionTask] = [.value(self)]
        while let task = stack.popLast() {
            switch task {
            case .text(let text):
                out += text
            case .value(.array(let elements)):
                out += "["
                stack.append(.text("]"))
                for index in elements.indices.reversed() {
                    stack.append(.value(elements[index]))
                    if index > elements.startIndex { stack.append(.text(", ")) }
                }
            case .value(.map(let entries)):
                out += "{"
                stack.append(.text("}"))
                let sorted = entries
                    .map { (encodedKey: $0.key.encode(), key: $0.key, value: $0.value) }
                    .sorted { $0.encodedKey.lexicographicallyPrecedes($1.encodedKey) }
                for index in sorted.indices.reversed() {
                    stack.append(.value(sorted[index].value))
                    stack.append(.text(": "))
                    stack.append(.value(sorted[index].key))
                    if index > sorted.startIndex { stack.append(.text(", ")) }
                }
            case .value(.tagged(let tag, let item)):
                out += "\(tag.rawValue)("
                stack.append(.text(")"))
                stack.append(.value(item))
            case .value(let scalar):
                scalar.appendScalarDescription(to: &out)
            }
        }
        return out
    }

    /// Append the diagnostic notation of a value with no nested items.
    private func appendScalarDescription(to out: inout String) {
        switch self {
        case .unsignedInt(let value):
            out += String(value)
        case .negativeInt(let value):
            // The value is -1 - `value`, which for the largest argument is one
            // past the range of every integer type.
            out += value == .max ? "-18446744073709551616" : "-" + String(value + 1)
        case .byteString(let bytes):
            out += "h'"
            for byte in bytes {
                out.unicodeScalars.append(hexDigits[Int(byte >> 4)])
                out.unicodeScalars.append(hexDigits[Int(byte & 0x0f)])
            }
            out += "'"
        case .textString(let string):
            appendQuoted(string, to: &out)
        case .simple(let value):
            out += "simple(\(value.rawValue))"
        case .bool(let value):
            out += value ? "true" : "false"
        case .null:
            out += "null"
        case .undefined:
            out += "undefined"
        case .half(let bits):
            // Via `Float`, which holds every half exactly, so the output is the
            // same on platforms without `Float16`.
            out += floatDescription(HalfPrecision.float(fromBits: bits)) + "_1"
        case .float(let value):
            out += floatDescription(value) + "_2"
        case .double(let value):
            out += floatDescription(value)
        case .array, .map, .tagged:
            break // containers are handled iteratively and never reach here
        }
    }
}

/// A pending piece of a value's description.
private enum DescriptionTask {
    case value(CBOR)
    case text(String)
}

private let hexDigits: [Unicode.Scalar] = Array("0123456789abcdef".unicodeScalars)

private func floatDescription<F: BinaryFloatingPoint & CustomStringConvertible>(_ value: F) -> String {
    if value.isNaN { return "NaN" }
    if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
    // Swift prints the shortest decimal that round-trips, and always includes a
    // decimal point or exponent, as diagnostic notation needs.
    return value.description
}

/// Append `string` in double quotes, escaped as a JSON string.
private func appendQuoted(_ string: String, to out: inout String) {
    out += "\""
    for scalar in string.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case "\u{08}": out += "\\b"
        case "\u{0C}": out += "\\f"
        case "\u{00}"..."\u{1F}":
            out += "\\u00"
            out.unicodeScalars.append(hexDigits[Int(scalar.value >> 4)])
            out.unicodeScalars.append(hexDigits[Int(scalar.value & 0x0f)])
        default:
            out.unicodeScalars.append(scalar)
        }
    }
    out += "\""
}
