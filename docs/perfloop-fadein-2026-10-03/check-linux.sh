#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "Usage: check-linux.sh BASE_CHECKOUT CHECKOUT OUTPUT_DIR" >&2
    exit 2
fi

base=$(cd "$1" && pwd)
checkout=$(cd "$2" && pwd)
mkdir -p "$3"
output=$(cd "$3" && pwd)
modules=$(go env GOMODCACHE)
cache=${SKIPPER_CHECK_GO_CACHE:-$output/go-cache}
mkdir -p "$output/docker-config" "$cache"
printf '{}\n' > "$output/docker-config/config.json"
export DOCKER_CONFIG="$output/docker-config"
export DOCKER_HOST="${DOCKER_HOST:-unix:///var/run/docker.sock}"

rm -f "$checkout/_test_plugins/filter_noop.so" \
    "$checkout/_test_plugins/predicate_match_none.so" \
    "$checkout/_test_plugins/dataclient_noop.so" \
    "$checkout/_test_plugins/multitype_noop.so" \
    "$checkout/_test_plugins_fail/fail.so"

set -- docker run --rm --network host --ulimit nofile=8192:8192 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$checkout:$checkout" \
    -v "$output/docker-config:/task-docker-config:ro" \
    -v "$modules:/go/pkg/mod" \
    -v "$cache:/root/.cache/go-build"
if [ "$base" != "$checkout" ]; then
    set -- "$@" -v "$base:$base:ro"
fi

set +e
"$@" \
    -e DOCKER_CONFIG=/task-docker-config \
    -e DOCKER_HOST=unix:///var/run/docker.sock \
    -e TESTCONTAINERS_RYUK_DISABLED=true \
    -e GOTOOLCHAIN=go1.27.0 \
    -e GOFLAGS=-p=1 \
    -e GOMAXPROCS=4 \
    -w "$checkout" \
    golang:1.26.6-bookworm \
    sh -c 'git config --global --add safe.directory "$PWD"; make shortcheck' \
    > "$output/shortcheck.log" 2>&1
rc=$?
set -e
printf '%s\n' "$rc" > "$output/shortcheck.exit"
exit "$rc"
