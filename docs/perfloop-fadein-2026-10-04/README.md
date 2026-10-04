# Fade-in endpoint-copy comparison

Native Verification passed with no findings. All four official performance
claims passed, each with ten paired samples.

| Algorithm | Base B/request | Repair B/request | Base allocations | Repair allocations |
| --- | ---: | ---: | ---: | ---: |
| Power of random choices | 38,976 | 25,406 | 182 | 181 |
| Random | 38,976 | 25,406 | 182 | 181 |
| Round robin | 38,976 | 25,406 | 182 | 181 |
| Consistent hash | 39,008 | 25,438 | 184 | 183 |

The reduction is 34.8% in each workload. Timing checks passed.

Scope: full `Proxy.ServeHTTP` requests, 200 distinct local HTTP 204 backends,
default Proxy transport, access logging disabled, one-hour fade-in, endpoint
age two hours, warmed requests, rotating `RemoteAddr`, and `GOMAXPROCS=1`.
Each sample ran for five seconds. Production traffic was not measured.

## Source and records

- Base: `3a146625f2b4f749fffcbabc9b6eab48e38aee4e`.
- Tested repair: `ede7dd6c074afbce7dff9d37ef49c61f92cac7d6`.
- Retained proof support: `aa293a3f641f0762d43b89295af399dc47b0f075`.
- [Exact source patch](source.patch).
- [Benchmark fixture](fadein_proof_test.go.txt).
- [Recorded decisions and aggregate statistics](results.json). These are
  official results, not raw sample logs.

The repair keeps a private filtered list for custom algorithms. The new public
regression test passes on the repair and fails when its defensive copy is removed.
Formatting, lint, targeted race tests, and repeated fade-in integration tests
passed. Full repository CI remains pending.

This evidence branch stores the comparison files. The benchmark fixture is
separate from the three-file contribution.

## Reproduce

Create two checkouts at the base commit. Apply `source.patch` in the candidate
checkout. Copy `fadein_proof_test.go.txt` to
`proxy/fadein_proof_test.go` in both checkouts.

Run the script with the control checkout, candidate checkout, and output folder:

```sh
bash measure.sh /path/to/control /path/to/candidate /path/to/results
benchstat /path/to/results/control.txt /path/to/results/candidate.txt
```

The script compiles both benchmark binaries, then runs ten alternating pairs
for each algorithm. It saves the toolchain, platform, and raw benchmark output.

Source patch SHA-256:
`d769d2c62e872e6a476988fd4b67984b2d5dfe15367a361db094a817e24223cf`.

Fixture SHA-256:
`e3a949661f4d6b52359fdad5cca6720468e26f53527574cd09b6b84fa7411ead`.
