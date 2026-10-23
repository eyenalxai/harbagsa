#!/bin/sh
set -eu

root=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
cd "$root"

if ! command -v flock >/dev/null 2>&1; then
	echo "tools/make.sh: flock is required to serialize builds" >&2
	exit 1
fi

mkdir -p .make
exec flock .make/harbagsa.lock make "$@"
