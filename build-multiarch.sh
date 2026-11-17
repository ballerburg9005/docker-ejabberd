#!/bin/sh
# Publish MIX and ECS with parallel multi-architecture Buildx by default.
# If Docker Hub rejects a multi-platform upload, retry as per-arch uploads.
# Usage: ./build-multiarch.sh [ejabberd-tag]
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VERSION=${1:-${VERSION:-26.09}}
PLATFORMS=${PLATFORMS:-linux/amd64,linux/arm64,linux/arm/v6,linux/arm/v7}
MIX_IMAGE=${MIX_IMAGE:-ballerburg9005/docker-ejabberd-mix-official-arm}
ECS_IMAGE=${ECS_IMAGE:-ballerburg9005/docker-ejabberd-ecs-official-arm}
PUBLISH_MODE=${PUBLISH_MODE:-auto}   # auto (parallel then fallback), parallel, split
SKIP_MIX=${SKIP_MIX:-0}             # Set to 1 when MIX:$VERSION already exists
PUSH_ATTEMPTS=${PUSH_ATTEMPTS:-3}
PUSH_RETRY_DELAY=${PUSH_RETRY_DELAY:-20}
VCS_REF=$(git -C "$root" rev-parse --short HEAD)
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

command -v docker >/dev/null 2>&1 || { echo "Docker is required" >&2; exit 1; }
docker buildx version >/dev/null
docker buildx inspect >/dev/null
case "$PUBLISH_MODE" in auto|parallel|split) ;; *) echo "Invalid PUBLISH_MODE: $PUBLISH_MODE" >&2; exit 2 ;; esac

retry() {
    attempt=1
    while :; do
        if "$@"; then return 0; fi
        if [ "$attempt" -ge "$PUSH_ATTEMPTS" ]; then
            echo "Failed after $attempt attempt(s): $*" >&2
            return 1
        fi
        echo "Upload failed ($attempt/$PUSH_ATTEMPTS); retrying in $PUSH_RETRY_DELAY s..." >&2
        sleep "$PUSH_RETRY_DELAY"
        attempt=$((attempt + 1))
    done
}

publish_split() {
    image=$1
    context=$2
    shift 2
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

    set -- -t "$image:$VERSION"
    if [ "$VERSION" != latest ]; then set -- "$@" -t "$image:latest"; fi
    for ref in $platform_refs; do set -- "$@" "$ref"; done
    retry docker buildx imagetools create "$@"
}

publish() {
    image=$1
    context=$2
    shift 2
    if [ "$PUBLISH_MODE" != split ]; then
        echo "Building and pushing $image:$VERSION in parallel ($PLATFORMS)"
        set -- "$@" -t "$image:$VERSION"
        if [ "$VERSION" != latest ]; then set -- "$@" -t "$image:latest"; fi
        if [ "$PUBLISH_MODE" = parallel ]; then
            retry docker buildx build \
                --platform "$PLATFORMS" \
                --provenance=false --sbom=false \
                "$@" --push "$context"
        elif docker buildx build \
            --platform "$PLATFORMS" \
            --provenance=false --sbom=false \
            "$@" --push "$context"; then
            :
        else
            echo "Parallel registry push failed; falling back to separate architecture uploads." >&2
            # The -t options added above must NOT be passed as build arguments
            # to publish_split. Reconstruct the original args from our caller.
            case "$image" in
                "$MIX_IMAGE") publish_split "$image" "$context" ;;
                "$ECS_IMAGE") publish_split "$image" "$context" \
                    --build-arg "VERSION=$VERSION" \
                    --build-arg "MIX_IMAGE=$MIX_IMAGE:$VERSION" \
                    --build-arg "VCS_REF=$VCS_REF" \
                    --build-arg "BUILD_DATE=$BUILD_DATE" ;;
            esac
        fi
    else
        publish_split "$image" "$context" "$@"
    fi
    docker buildx imagetools inspect "$image:$VERSION"
}

if [ "$SKIP_MIX" = 1 ]; then
    echo "Skipping MIX build; verifying existing $MIX_IMAGE:$VERSION"
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
