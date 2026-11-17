#!/bin/sh
# Build and publish the original Docker Hub images as one multi-arch manifest.
# Usage: ./build-multiarch.sh [ejabberd-tag]
# Can also be invoked via: cd ecs && ./build.sh [ejabberd-tag]
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VERSION=${1:-${VERSION:-26.09}}
PLATFORMS=${PLATFORMS:-linux/amd64,linux/arm64,linux/arm/v6,linux/arm/v7}
MIX_IMAGE=${MIX_IMAGE:-ballerburg9005/docker-ejabberd-mix-official-arm}
ECS_IMAGE=${ECS_IMAGE:-ballerburg9005/docker-ejabberd-ecs-official-arm}
VCS_REF=$(git -C "$root" rev-parse --short HEAD)
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

command -v docker >/dev/null 2>&1 || { echo "Docker is required" >&2; exit 1; }
docker buildx version >/dev/null
docker buildx inspect >/dev/null

echo "Building MIX: $MIX_IMAGE:$VERSION ($PLATFORMS)"
set -- -t "$MIX_IMAGE:$VERSION"
if [ "$VERSION" != latest ]; then set -- "$@" -t "$MIX_IMAGE:latest"; fi
docker buildx build \
    --platform "$PLATFORMS" \
    "$@" --push "$root/mix"

echo "Building ECS: $ECS_IMAGE:$VERSION ($PLATFORMS)"
set -- -t "$ECS_IMAGE:$VERSION"
if [ "$VERSION" != latest ]; then set -- "$@" -t "$ECS_IMAGE:latest"; fi
docker buildx build \
    --platform "$PLATFORMS" \
    --build-arg VERSION="$VERSION" \
    --build-arg MIX_IMAGE="$MIX_IMAGE:$VERSION" \
    --build-arg VCS_REF="$VCS_REF" \
    --build-arg BUILD_DATE="$BUILD_DATE" \
    "$@" --push "$root/ecs"

echo "Published:"
docker buildx imagetools inspect "$ECS_IMAGE:$VERSION"
