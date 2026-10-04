#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "Usage: measure.sh CONTROL_CHECKOUT PATCHED_CHECKOUT OUTPUT_DIR" >&2
    exit 2
fi

control=$1
candidate=$2
output=$3
mkdir -p "$output"
output=$(cd "$output" && pwd)

(cd "$control" && go test -c -o "$output/control-proxy.test" ./proxy)
(cd "$candidate" && go test -c -o "$output/candidate-proxy.test" ./proxy)

for round in 1 2 3 4 5 6; do
    case "$round" in
        1|3|5) order="control candidate" ;;
        *) order="candidate control" ;;
    esac
    for arm in $order; do
        echo "Round $round: $arm"
        "$output/$arm-proxy.test" \
            -test.run='^$' \
            -test.bench='^BenchmarkFadeInProofServeHTTP$' \
            -test.benchtime=1s \
            -test.benchmem \
            -test.cpu=1 \
            -test.count=1 > "$output/$arm-round-$round.txt" 2>&1
    done
done

cat "$output"/control-round-*.txt > "$output/control.txt"
cat "$output"/candidate-round-*.txt > "$output/candidate.txt"
