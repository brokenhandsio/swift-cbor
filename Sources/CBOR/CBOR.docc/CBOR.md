# ``CBOR``

A modern, memory-safe CBOR (Concise Binary Object Representation, RFC 8949) library
for Swift.

## Overview

swift-cbor decodes and encodes CBOR through a simple value model, ``CBOR``, and also
bridges any `Codable` type via ``CBOREncoder`` and ``CBORDecoder``.

Decoding reads through `Span<UInt8>` using only bounds-checked access, so the library
contains no `unsafe` code and builds under strict memory safety. Encoding is
deterministic by default (shortest-form integers and canonically ordered map keys, per
RFC 8949 §4.2).

```swift
import CBOR

// Value model
let value = try CBOR.decode([0x83, 0x01, 0x02, 0x03]) // .array([1, 2, 3])
let bytes = value.encode()

// Codable bridge
struct Reading: Codable { var sensor: String; var value: Double }
let encoded = try CBOREncoder().encode(Reading(sensor: "abc", value: 1.5))
let reading = try CBORDecoder().decode(Reading.self, from: encoded)
```

## Topics

### The value model

- ``CBOR``
- ``CBORTag``

### Decoding and encoding

- ``CBOREncoder``
- ``CBORDecoder``
- ``CBOROptions``

### Errors

- ``CBORError``
