#!/usr/bin/env bash
# One-command local GitOps environment:
#   kind cluster -> ingress-nginx -> ShopStream images -> Argo CD -> root app (app-of-apps)
#   -> Argo CD syncs dev (infra wave -1, app wave 0) -> http://localhost:4780
#
# Usage: scripts/bootstrap-kind.sh
# Env:
#   GITOPS_SOURCE=local|github   where Argo CD reads this repo from (default: local — serves the
#                                committed HEAD of this checkout, no push required)
#   IMAGE_SOURCE=auto|build|pull images: reuse local / pull from GHCR / build from source (default: auto)
#   SHOPSTREAM_SRC=../shopstream app source used when images must be built
#   SKIP_SMOKE=1                 skip the end-to-end smoke test at the end
source "$(dirname "$0")/lib.sh"
need docker kind kubectl git node

CLUSTER="${CLUSTER_NAME:-shopstream}"
GITOPS_SOURCE="${GITOPS_SOURCE:-local}"
IMAGE_SOURCE="${IMAGE_SOURCE:-auto}"
INGRESS_NGINX_VERSION="${INGRESS_NGINX_VERSION:-controller-v1.15.1}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v3.5.4}"
APP_URL="http://localhost:4780"
TAG="$(dev_image_tag)"

# --- 1. cluster -------------------------------------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  log "kind cluster '$CLUSTER' already exists — reusing it"
else
  log "creating kind cluster '$CLUSTER'"
  kind create cluster --name "$CLUSTER" --config "$ROOT_DIR/scripts/kind-config.yaml" --wait 120s
fi
kubectl config use-context "kind-$CLUSTER" >/dev/null

# --- 2. ingress-nginx -----------------------------------------------------------------------------
log "installing ingress-nginx ($INGRESS_NGINX_VERSION)"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/$INGRESS_NGINX_VERSION/deploy/static/provider/kind/deploy.yaml" >/dev/null
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s >/dev/null
ok "ingress-nginx ready"

# --- 3. images ----------------------------------------------------------------------------------
log "making ShopStream images ($REGISTRY/shopstream-*:$TAG) available to the cluster"
missing=()
for img in "${IMAGES[@]}"; do
  ref="$REGISTRY/shopstream-$img:$TAG"
  if [[ "$IMAGE_SOURCE" != "build" ]] && docker image inspect "$ref" >/dev/null 2>&1 && [[ "$IMAGE_SOURCE" == "auto" ]]; then
    continue
  fi
  if [[ "$IMAGE_SOURCE" != "build" ]] && docker pull -q "$ref" >/dev/null 2>&1; then
    continue
  fi
  missing+=("$img")
done
if (( ${#missing[@]} > 0 )); then
  warn "not available locally or on GHCR: ${missing[*]} — building from source"
  TAG="$TAG" "$ROOT_DIR/scripts/build-images.sh"
fi
for img in "${IMAGES[@]}"; do
  kind load docker-image --name "$CLUSTER" "$REGISTRY/shopstream-$img:$TAG" >/dev/null
done
ok "images loaded into kind"

# --- 4. Argo CD ---------------------------------------------------------------------------------
log "installing Argo CD ($ARGOCD_VERSION)"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml" >/dev/null
kubectl -n argocd patch configmap argocd-cm --type merge --patch-file "$ROOT_DIR/argocd/bootstrap/argocd-cm-patch.yaml" >/dev/null
# Faster reconciliation for local demos (default is 3 minutes).
kubectl -n argocd patch configmap argocd-cm --type merge -p '{"data":{"timeout.reconciliation":"30s"}}' >/dev/null
for d in argocd-repo-server argocd-server argocd-applicationset-controller; do
  kubectl -n argocd rollout restart deploy/$d >/dev/null
done
kubectl -n argocd rollout restart statefulset/argocd-application-controller >/dev/null
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s >/dev/null
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s >/dev/null
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s >/dev/null
ok "Argo CD ready"

# --- 5. root application (app-of-apps) ------------------------------------------------------------
if [[ "$GITOPS_SOURCE" == "local" ]]; then
  REPO_URL="$("$ROOT_DIR/scripts/local-git-server.sh")"
  REVISION="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)"
  [[ "$REVISION" == "HEAD" ]] && REVISION="$(git -C "$ROOT_DIR" rev-parse HEAD)"
else
  REPO_URL="https://github.com/rajak312/shopstream-gitops.git"
  REVISION="${GITOPS_REVISION:-main}"
fi
log "pointing Argo CD at $REPO_URL ($REVISION)"
sed -e "s#https://github.com/rajak312/shopstream-gitops.git#$REPO_URL#g" \
    -e "s#targetRevision: main#targetRevision: $REVISION#g" \
    "$ROOT_DIR/argocd/root-app.yaml" | kubectl apply -n argocd -f - >/dev/null

app_ready() {
  [[ "$(kubectl -n argocd get application "$1" -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)" == "Synced/Healthy" ]]
}
wait_for "Argo CD synced shopstream-dev-infra (MongoDB, PostgreSQL, NATS)" 900 app_ready shopstream-dev-infra
wait_for "Argo CD synced shopstream-dev (gateway, subgraphs, web)" 900 app_ready shopstream-dev
kubectl -n shopstream-dev rollout status deploy --timeout=300s >/dev/null

# --- 6. verify ------------------------------------------------------------------------------------
if [[ "${SKIP_SMOKE:-0}" != "1" ]]; then
  log "running the checkout smoke test through the ingress"
  GATEWAY_URL="$APP_URL/graphql" node "$ROOT_DIR/scripts/smoke-test.mjs"
fi

ARGO_PASS="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
cat <<MSG

$(ok "ShopStream is running on kind")
  Storefront      $APP_URL            (demo@shopstream.dev / demo-password)
  Event flow      $APP_URL/flow
  GraphQL         $APP_URL/graphql
  Argo CD UI      kubectl -n argocd port-forward svc/argocd-server 4781:443  ->  https://localhost:4781
                  user: admin   password: $ARGO_PASS
  Tear down       kind delete cluster --name $CLUSTER && docker rm -f shopstream-gitops-git
MSG
