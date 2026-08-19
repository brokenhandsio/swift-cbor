# Seeds

Curated starting inputs. libFuzzer is given these directories *after* `Corpus/`,
which makes them read-only: discoveries are written to the corpus and never
here.

Keep them separate from the corpus deliberately. `-merge=1` rewrites the
directory it minimizes, keeping the smallest set that preserves coverage — and a
specification vector whose coverage is reachable some other way is exactly what
it drops. These files were lost that way once already, when seeds and
discoveries shared a directory.

## Provenance

- `CBORDecode/rfc8949-*`, `CBORRoundTrip/rfc8949-*` — the example encodings from
  [RFC 8949 Appendix A](https://www.rfc-editor.org/rfc/rfc8949.html#appendix-A),
  one file per vector, named after the leading bytes of its hex encoding. They
  cover every major type, both indefinite-length forms, the three float widths,
  tags, and the simple values.
- `CBORDeepNesting/nested-indefinite-arrays` — 20,000 × `0x9f`, an
  indefinite-length array nested 20,000 deep. Generated, not curated, but worth
  protecting for the same reason: it is the input that makes the deep-nesting
  target productive from the first run, and one byte of input is one level of
  nesting.

Adding more is just a matter of dropping files in.
