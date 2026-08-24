# Benchmark thresholds

Absolute p90 ceilings for `mallocCountTotal`, checked in CI by
`swift package benchmark thresholds check`.

## Do not regenerate these with `thresholds update`

In package-benchmark 1.36.2, `update` and `check` disagree on where these files
live. `update` slugifies the benchmark name — `Decode/COSE key` becomes
`CBORBenchmarks.Decode_COSE_key.p90.json` — while `check` builds the path from
the raw name, so it looks for `CBORBenchmarks.Decode/COSE key.p90.json`, with
the slash as a directory separator. Files written by `update` are therefore
never found, and the check fails with "Could not find any matching absolute
thresholds" no matter what they contain. The layout here is what `check` reads.

## Why only `mallocCountTotal`

`instructions` is not measured on CI at all: GitHub's containers do not expose
the perf counters it needs, so the metric is simply absent from the Linux run
even though it appears locally on macOS. `peakMemoryResident` is measured but is
a whole-process high-water mark that moves with allocator behaviour and runner
image, which would produce flaky failures rather than signal.

That leaves allocation count, which is deterministic and is the metric these
benchmarks were written to defend.

## Values

These are **pins, not ceilings**. `thresholds check` requires the run to be
exactly equal and exits non-zero for improvements as well as regressions — by
design, so a gain is recorded deliberately rather than silently absorbed. If a
change makes something allocate less, update the number in the same commit and
say so in the message.

Values are CI's measured p90 for `mallocCountTotal`, taken from the
`Benchmarks (Linux)` job. They are platform-specific: a local run on macOS or on
arm64 will report different counts and fail this check. That is expected —
the gate is a CI gate.
