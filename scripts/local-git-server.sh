#!/usr/bin/env bash
# Serves the *committed* HEAD of this repository over git smart-HTTP on the kind
# docker network, so Argo CD can sync from a local checkout (no push needed).
# Prints the repo URL reachable from inside the cluster.
source "$(dirname "$0")/lib.sh"
need docker git

NAME="${GIT_SERVER_NAME:-shopstream-gitops-git}"
SNAPSHOT="${TMPDIR:-/tmp}/shopstream-gitops-snapshot.git"

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
  warn "uncommitted changes are NOT served — Argo CD only sees committed HEAD ($(git -C "$ROOT_DIR" rev-parse --short HEAD))" >&2
fi
rm -rf "$SNAPSHOT"
git clone -q --bare "$ROOT_DIR" "$SNAPSHOT"
chmod -R a+rX "$SNAPSHOT"

docker build -q -t shopstream-gitops/git-server:local "$ROOT_DIR/scripts/git-server" >/dev/null 2>&1
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --network kind --restart unless-stopped \
  -v "$SNAPSHOT:/srv/git/shopstream-gitops.git:ro" shopstream-gitops/git-server:local >/dev/null
IP="$(docker inspect -f '{{(index .NetworkSettings.Networks "kind").IPAddress}}' "$NAME")"
echo "http://$IP:8080/shopstream-gitops.git"
