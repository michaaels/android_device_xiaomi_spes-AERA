#!/bin/bash
# Host helper: build the image and start the build container.
#   tools/docker/run.sh            -> build image + start container "aera-spes"
#   docker exec -it -u builder -w /src aera-spes bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TREE="$(cd "$HERE/../.." && pwd)"
STORE="${AERA_STORE:-/mnt/2E6421A46421702F/aera_source}"
IMAGE_FILE="${AERA_IMAGE_FILE:-aera_src.ext4}"

docker build -t aera-spes-build:24.04 \
    --build-arg USER_UID="$(id -u)" --build-arg USER_GID="$(id -g)" "$HERE"

docker rm -f aera-spes >/dev/null 2>&1 || true
# --privileged is required only for the loop mount of $IMAGE_FILE.
docker run -d --name aera-spes --privileged \
    --security-opt label=disable \
    -e AERA_IMAGE="/store/$IMAGE_FILE" \
    -v "$STORE":/store \
    -v "$TREE":/devtree \
    aera-spes-build:24.04

sleep 2
docker logs aera-spes
