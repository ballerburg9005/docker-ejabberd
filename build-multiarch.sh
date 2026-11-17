#!/bin/sh
# Build and publish multi-platform MIX + ECS images to the original Docker Hub names.
# Push individual architectures first to avoid a single large, concurrent registry
# upload. Assemble the normal multi-platform tags only after every arch succeeds.
# Usage: ./build-multiarch.sh [ejabberd-tag]
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VERSION=${1:-${VERSION:-26.09}}
PLATFORMS=${PLATFORMS:-linux/amd64,linux/arm64,linux/arm/v6,linux/arm/v7}
MIX_IMAGE=${MIX_IMAGE:-ballerburg9005/docker-ejabberd-mix-official-arm}
ECS_IMAGE=${ECS_IMAGE:-ballerburg9005/docker-ejabberd-ecs-official-arm}
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
        echo "Registry push failed (attempt $attempt/$PUSH_ATTEMPTS); retrying in $PUSH_RETRY_DELAY seconds with BuildKit cache..." >&2
        sleep "$PUSH_RETRY_DELAY"
        attempt=$((attempt + 1))
    done
}

publish() {
    image=$1
    context=$2
    shift 2
    # The remaining arguments are forwarded to each build (e.g., --build-arg).
    platform_refs=
    for platform in $(printf '%s' "$PLATFORMS" | tr ',' ' '); do
        suffix=$(printf '%s' "$platform" | sed 's|^linux/||; s|/|-|g')
        ref="$image:$VERSION-$suffix"
        echo "Building and pushing $ref ($platform)"
        retry docker buildx build \
            --platform "$platform" \
            --provenance=false --sbom=false \
            "$@" --push -t "$ref" "$context"
        platform_refs="$platform_refs $ref"
    done

    # Manifest assembly never uploads the large layers again. Keep the original
    # unversioned (:latest) and versioned multi-platform image names.
    set -- -t "$image:$VERSION"
    if [ "$VERSION" != latest ]; then set -- "$@" -t "$image:latest"; fi
    for ref in $platform_refs; do set -- "$@" "$ref"; done
    echo "Publishing multi-platform manifest: $image:$VERSION"
    retry docker buildx imagetools create "$@"
    docker buildx imagetools inspect "$image:$VERSION"
}

publish "$MIX_IMAGE" "$root/mix"
publish "$ECS_IMAGE" "$root/ecs" \
    --build-arg "VERSION=$VERSION" \
    --build-arg "MIX_IMAGE=$MIX_IMAGE:$VERSION" \
    --build-arg "VCS_REF=$VCS_REF" \
    --build-arg "BUILD_DATE=$BUILD_DATE"

echo "Published both multi-platform images successfully."
