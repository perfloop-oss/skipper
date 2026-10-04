#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: measure.sh CONTROL CANDIDATE RESULTS" >&2
  exit 2
fi
proof_control=$(cd "$1" && pwd)
proof_candidate=$(cd "$2" && pwd)
mkdir -p "$3"
proof_results=$(cd "$3" && pwd)
go version > "$proof_results/environment.txt"
go env GOOS GOARCH >> "$proof_results/environment.txt"

(cd "$proof_control" && go test -c -o "$proof_results/control.test" ./proxy)
(cd "$proof_candidate" && go test -c -o "$proof_results/candidate.test" ./proxy)

for algorithm in powerOfRandomNChoices random roundRobin consistentHash; do
  for pair in {1..10}; do
    if (( pair % 2 )); then
      arms=(control candidate)
    else
      arms=(candidate control)
    fi
    for arm in "${arms[@]}"; do
      if [ "$arm" = control ]; then
        proof_source=$proof_control
      else
        proof_source=$proof_candidate
      fi
      (
        cd "$proof_source"
        "$proof_results/$arm.test" \
          -test.run='^$' \
          -test.bench="^BenchmarkFadeInProofServeHTTP/$algorithm/endpoints=200$" \
          -test.count=1 -test.benchmem -test.cpu=1 -test.benchtime=5s
      ) > "$proof_results/$algorithm-$pair-$arm.txt"
    done
  done
done

cat "$proof_results/"*-control.txt > "$proof_results/control.txt"
cat "$proof_results/"*-candidate.txt > "$proof_results/candidate.txt"
