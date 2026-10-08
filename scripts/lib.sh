# Shared helpers for the scripts in this directory.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REGISTRY:-ghcr.io/rajak312}"
SERVICES=(gateway catalog orders payments notifications)
IMAGES=("${SERVICES[@]}" web)

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok() { printf '\033[1;32m ✔\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m ✖\033[0m %s\n' "$*" >&2; exit 1; }

need() {
  for bin in "$@"; do command -v "$bin" >/dev/null 2>&1 || die "missing required tool: $bin"; done
}

# Image tag deployed to dev (bumped by the shopstream release workflow).
dev_image_tag() {
  awk '/^global:/{g=1} g&&/^  image:/{i=1} g&&i&&/^    tag:/{print $2; exit}' "$ROOT_DIR/environments/dev/values.yaml" | tr -d '"'
}

# Polls a command until it succeeds or the timeout (seconds) expires.
wait_for() {
  local desc="$1" timeout="$2"; shift 2
  local start=$SECONDS
  until "$@" >/dev/null 2>&1; do
    if (( SECONDS - start > timeout )); then die "timed out after ${timeout}s waiting for: $desc"; fi
    sleep 5
  done
  ok "$desc"
}
