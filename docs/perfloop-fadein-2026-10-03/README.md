# Skipper fade-in allocation proof

Status: local proof complete; upstream review pending. October 3, 2026.

[Patch commit](https://github.com/perfloop-oss/skipper/commit/3fec8811ee683c2713a72059ad7a5cc007c59107),
on upstream `3a146625f2b4f749fffcbabc9b6eab48e38aee4e`.
The source change allocates a filtered endpoint list only after it drops an
endpoint. After fade-in completes, it returns the input list. It keeps endpoint
order and the fallback when all endpoints drop. Two changed files include one
test, with 22 inserted lines and three deleted lines.

## Method

The benchmark calls `Proxy.ServeHTTP` using the default transport and distinct
local HTTP backends that return 204. Fade-in lasts one hour; endpoints are two
hours old. Connections are warmed before measurement. Each operation creates
a request and response recorder, then checks the response. Both builds use the
same fixture. Only `proxy/fadein.go` differs.

Six samples per build, alternating build order; one second per benchmark;
`GOMAXPROCS=1`. Four load-balancing algorithms, with 1, 8, 32, or 200 endpoints.
Apple M5 Max, macOS 26.6.2, darwin/arm64, Go 1.27.0. No CPU core pinning.

## Results

Median bytes allocated per request for `roundRobin`:

| Endpoints | Base B/request | Patch B/request | Reduction |
| --- | ---: | ---: | ---: |
| 1 | 25,410 | 25,346 | 0.25% |
| 8 | 25,858 | 25,346 | 1.98% |
| 32 | 27,649 | 25,345 | 8.33% |
| 200 | 38,911 | 25,342 | 34.87% |

All four algorithms remove one allocation per request. At 200 endpoints, the
allocated-byte reduction is 34.84% to 34.87%. Each comparison has six samples
per build; `benchstat` reports `p=0.002` for allocated bytes. All 192 measured
benchmark records passed their response checks. Elapsed time was noisy; no
general latency gain is claimed.

Raw results: [base](control.txt), [patch](candidate.txt),
[benchstat](benchstat.txt), [allocation table](allocation-results.csv).

## Checks

`make fmt` and `make lint` passed. The slice-reuse test fails on unchanged source
and passes with the patch. Its race check passed. Full `make shortcheck` passed
on unchanged source and the patch in Linux with Docker services, Go 1.27.0,
`GOFLAGS=-p=1`, and `GOMAXPROCS=4`. The unchanged source needed one rerun after
`TestBackendTimeoutWithSlowResponseHeadersShadow` exceeded its client timeout.

## Reproduce

Use two checkouts at patch commit `3fec8811ee683c2713a72059ad7a5cc007c59107`.
In the control checkout, restore only `proxy/fadein.go` from upstream commit
`3a146625f2b4f749fffcbabc9b6eab48e38aee4e`. Copy
`proxy/fadein_proof_test.go` from this evidence branch into both checkouts.
Thus both builds contain the same test files; only the production file differs.
The reuse test is expected to fail on control. The measurement script runs
benchmarks only. Check unchanged upstream and the patch before measuring,
then run:

```sh
sh measure.sh /path/to/control /path/to/patched /path/to/results
benchstat /path/to/results/control.txt /path/to/results/candidate.txt
```

`check-linux.sh` records full repository checks with an empty Docker config:

```sh
sh check-linux.sh /path/to/base /path/to/checkout /path/to/check-results
```

These results apply to requests after fade-in completes. They do not establish
Zalando production savings or retained heap reduction. Target CI is pending.
