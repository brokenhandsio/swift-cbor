/// Options controlling CBOR decoding and encoding.
public struct CBOROptions: Sendable {
    /// The maximum nesting depth to decode, inclusive.
    ///
    /// A top-level primitive has depth 0; each nested array, map or tag increases
    /// the depth by one. Decoding throws ``CBORError/maxDepthExceeded(_:)`` when the
    /// limit would be exceeded. This bounds stack usage on adversarial input.
    /// Defaults to `512`.
    public var maximumDepth: Int

    /// When decoding, throw ``CBORError/duplicateMapKey`` if a map contains the same
    /// key more than once. Defaults to `false`.
    public var rejectDuplicateMapKeys: Bool

    /// When encoding, produce RFC 8949 §4.2 "core deterministic" output: integers
    /// and floats use their shortest form and map keys are sorted into bytewise
    /// lexicographic order of their encodings. Defaults to `true`.
    ///
    /// Because ``CBOR/map(_:)`` is backed by an unordered dictionary, deterministic
    /// ordering is the only stable ordering available; disabling this only relaxes
    /// the shortest-form guarantees, not key ordering.
    public var deterministic: Bool

    public init(
        maximumDepth: Int = 512,
        rejectDuplicateMapKeys: Bool = false,
        deterministic: Bool = true
    ) {
        self.maximumDepth = maximumDepth
        self.rejectDuplicateMapKeys = rejectDuplicateMapKeys
        self.deterministic = deterministic
    }

    /// The default options.
    public static let `default` = CBOROptions()
}
