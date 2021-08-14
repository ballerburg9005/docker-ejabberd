#!/bin/sh

current=$(date +%y.07)
version=${1:-$current}
#--platform linux/arm64,linux/amd64,linux/armhf \
docker buildx build --platform linux/arm64,linux/amd64,linux/armhf \
    --build-arg VERSION=$version \
    --build-arg VCS_REF=`git rev-parse --short HEAD` \
    --build-arg BUILD_DATE=`date -u +"%Y-%m-%dT%H:%M:%SZ"` \
    --push -t ballerburg9005/docker-ejabberd-ecs-official-arm .
#[ "$version" = "latest" ] || docker tag ejabberd/ecs:$version ejabberd/ecs:latest
