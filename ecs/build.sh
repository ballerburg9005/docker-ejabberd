#!/bin/sh
# Backwards-compatible entry point: builds and pushes both multi-arch images.
set -eu
dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$dir/../build-multiarch.sh" "$@"
