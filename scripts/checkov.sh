#!/usr/bin/env bash
# Checkov policy scan of the rendered production manifests (dev intentionally tracks a moving tag) and the Terraform module
# (runs the official container image, so nothing needs to be installed).
source "$(dirname "$0")/lib.sh"
need helm docker
OUT="$ROOT_DIR/rendered-checkov"
rm -rf "$OUT" && mkdir -p "$OUT"
for c in shopstream shopstream-infra; do helm dependency build "$ROOT_DIR/charts/$c" >/dev/null; done
helm template shopstream "$ROOT_DIR/charts/shopstream" -n shopstream-prod -f "$ROOT_DIR/environments/prod/values.yaml" > "$OUT/prod-app.yaml"
helm template shopstream-infra "$ROOT_DIR/charts/shopstream-infra" -n shopstream-prod -f "$ROOT_DIR/environments/prod/infra-values.yaml" > "$OUT/prod-infra.yaml"

# Deliberate skips (documented in README):
#   CKV_K8S_43 image digest  -> immutable git-SHA tags instead
#   CKV_K8S_15 pull Always   -> IfNotPresent is correct for immutable tags
#   CKV_K8S_21 namespace     -> set by Argo CD / helm -n at deploy time
#   CKV_K8S_35 secret env    -> 12-factor services read connection strings from env (sourced from a Secret)
SKIP="CKV_K8S_43,CKV_K8S_15,CKV_K8S_21,CKV_K8S_35"
docker run --rm -v "$ROOT_DIR:/repo" -w /repo bridgecrew/checkov:3 \
  -d rendered-checkov --framework kubernetes --skip-check "$SKIP" --compact
docker run --rm -v "$ROOT_DIR:/repo" -w /repo bridgecrew/checkov:3 \
  -d infra/terraform/hetzner --framework terraform --compact
ok "checkov: no failed checks"
