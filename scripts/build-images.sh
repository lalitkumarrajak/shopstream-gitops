#!/usr/bin/env bash
# Builds the ShopStream images from a source checkout of github.com/rajak312/shopstream,
# tagged exactly as the dev environment expects, so the kind cluster works even before
# any image has been published to GHCR.
#
#   SHOPSTREAM_SRC=../shopstream TAG=latest scripts/build-images.sh
source "$(dirname "$0")/lib.sh"
need docker git

TAG="${TAG:-$(dev_image_tag)}"
SRC="${SHOPSTREAM_SRC:-$ROOT_DIR/../shopstream}"
if [[ ! -f "$SRC/docker/service.Dockerfile" ]]; then
  SRC="${TMPDIR:-/tmp}/shopstream-src"
  log "cloning https://github.com/rajak312/shopstream into $SRC"
  rm -rf "$SRC" && git clone --depth 1 https://github.com/rajak312/shopstream "$SRC"
fi
log "building ShopStream images from $SRC (tag: $TAG)"

for svc in "${SERVICES[@]}"; do
  docker build -q -f "$SRC/docker/service.Dockerfile" --build-arg "SERVICE=$svc" \
    -t "$REGISTRY/shopstream-$svc:$TAG" "$SRC" >/dev/null
  ok "$REGISTRY/shopstream-$svc:$TAG"
done
# The storefront talks to the gateway through the same ingress host (/graphql, /events).
docker build -q -f "$SRC/apps/web/Dockerfile" \
  --build-arg NEXT_PUBLIC_GATEWAY_URL=/graphql \
  --build-arg NEXT_PUBLIC_SITE_URL=http://localhost:4780 \
  -t "$REGISTRY/shopstream-web:$TAG" "$SRC" >/dev/null
ok "$REGISTRY/shopstream-web:$TAG"
