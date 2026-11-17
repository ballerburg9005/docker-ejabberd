#!/bin/sh
# Always build and publish all target architectures together using Buildx.
# On registry failure, retry the same parallel multi-platform build.
# Usage: ./build-multiarch.sh [ejabberd-tag]
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VERSION=${1:-${VERSION:-26.09}}
PLATFORMS=${PLATFORMS:-linux/amd64,linux/arm64,linux/arm/v6,linux/arm/v7}
MIX_IMAGE=${MIX_IMAGE:-ballerburg9005/docker-ejabberd-mix-official-arm}
ECS_IMAGE=${ECS_IMAGE:-ballerburg9005/docker-ejabberd-ecs-official-arm}
SKIP_MIX=${SKIP_MIX:-0}  # 1 to use an already published MIX:$VERSION image
PUSH_ATTEMPTS=${PUSH_ATTEMPTS:-3}
PUSH_RETRY_DELAY=${PUSH_RETRY_DELAY:-20}
VCS_REF=$(git -C "$root" rev-parse --short HEAD)
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

command -v docker >/dev/null 2>&1 || { echo "Docker is required" >&2; exit 1; }
docker buildx version >/dev/null
docker buildx inspect >/dev/null

retry() {
    attempt=1
    while :; do
        if "$@"; then return 0; fi
        if [ "$attempt" -ge "$PUSH_ATTEMPTS" ]; then
            echo "Failed after $attempt attempt(s): $*" >&2
            return 1
        fi
        echo "Multi-platform push failed ($attempt/$PUSH_ATTEMPTS); retrying the same parallel build in $PUSH_RETRY_DELAY seconds..." >&2
        sleep "$PUSH_RETRY_DELAY"
        attempt=$((attempt + 1))
    done
}

publish() {
    image=$1
    context=$2
    shift 2
    set -- "$@" -t "$image:$VERSION"
    if [ "$VERSION" != latest ]; then set -- "$@" -t "$image:latest"; fi
    echo "Building and pushing $image:$VERSION ($PLATFORMS, together)"
    retry docker buildx build \
        --platform "$PLATFORMS" \
        --provenance=false --sbom=false \
        "$@" --push "$context"
    docker buildx imagetools inspect "$image:$VERSION"
}

if [ "$SKIP_MIX" = 1 ]; then
    echo "Skipping MIX build; checking existing $MIX_IMAGE:$VERSION"
    docker buildx imagetools inspect "$MIX_IMAGE:$VERSION"
else
    publish "$MIX_IMAGE" "$root/mix"
fi
publish "$ECS_IMAGE" "$root/ecs" \
    --build-arg "VERSION=$VERSION" \
    --build-arg "MIX_IMAGE=$MIX_IMAGE:$VERSION" \
    --build-arg "VCS_REF=$VCS_REF" \
    --build-arg "BUILD_DATE=$BUILD_DATE"

echo "Published ECS multi-platform image: $ECS_IMAGE:$VERSION"
