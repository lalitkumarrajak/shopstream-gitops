#!/usr/bin/env bash
# Static validation, identical to CI: helm lint, helm template for every environment,
# kubeconform (Kubernetes + CRD schemas) and kube-score policy checks.
source "$(dirname "$0")/lib.sh"
need helm kubeconform kube-score
OUT="${OUT_DIR:-$ROOT_DIR/.rendered}"
K8S_VERSION="${K8S_VERSION:-1.33.0}"
rm -rf "$OUT" && mkdir -p "$OUT"

log "helm dependency build"
for c in shopstream shopstream-infra; do helm dependency build "$ROOT_DIR/charts/$c" >/dev/null; done

log "helm lint"
helm lint "$ROOT_DIR/charts/shopstream-lib" "$ROOT_DIR/argocd/apps"
for env in dev prod; do
  helm lint "$ROOT_DIR/charts/shopstream" -f "$ROOT_DIR/environments/$env/values.yaml"
  helm lint "$ROOT_DIR/charts/shopstream-infra" -f "$ROOT_DIR/environments/$env/infra-values.yaml"
done

log "helm template"
for env in dev prod; do
  helm template shopstream "$ROOT_DIR/charts/shopstream" -n "shopstream-$env" \
    -f "$ROOT_DIR/environments/$env/values.yaml" > "$OUT/$env-app.yaml"
  helm template shopstream-infra "$ROOT_DIR/charts/shopstream-infra" -n "shopstream-$env" \
    -f "$ROOT_DIR/environments/$env/infra-values.yaml" > "$OUT/$env-infra.yaml"
done
helm template shopstream-apps "$ROOT_DIR/argocd/apps" -n argocd > "$OUT/argocd-apps.yaml"
cp "$ROOT_DIR/argocd/root-app.yaml" "$OUT/argocd-root.yaml"
ok "rendered $(cat "$OUT"/*.yaml | grep -c '^kind:') manifests into $OUT"

log "kubeconform (Kubernetes $K8S_VERSION + CRDs catalog)"
kubeconform -strict -summary -kubernetes-version "$K8S_VERSION" \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  "$OUT"/*.yaml

log "kube-score (workload policies)"
# Ignored checks are deliberate and documented in the README (security hardening checklist):
#  - image pull policy: tags are immutable git SHAs, so IfNotPresent is correct
#  - CPU limits != requests: burstable QoS on purpose for Node.js services
#  - ephemeral storage: bounded by emptyDir sizeLimit instead
#  - host anti-affinity: topologySpreadConstraints are used instead
#  - single replicas in dev only
#  - identical probes: liveness (/health) and readiness (/ready) differ for backends; web serves both on /
: > "$OUT/kube-score.txt"
for env in dev prod; do
  # dev deliberately runs single replicas on a laptop-sized kind cluster
  extra=(); [[ "$env" == "dev" ]] && extra=(--ignore-test deployment-replicas)
  kube-score score "$OUT/$env-app.yaml" "$OUT/$env-infra.yaml" \
    --output-format ci \
    --ignore-test container-image-pull-policy \
    --ignore-test container-image-tag \
    --ignore-test pod-probes-identical \
    --ignore-test container-ephemeral-storage-request-and-limit \
    --ignore-test container-cpu-requests-equal-limits \
    --ignore-test container-memory-requests-equal-limits \
    --ignore-test deployment-has-host-podantiaffinity \
    --ignore-test statefulset-has-host-podantiaffinity \
    --enable-optional-test container-seccomp-profile \
    "${extra[@]}" \
    >> "$OUT/kube-score.txt" || true
done
if grep -E '\[(CRITICAL|WARNING)\]' "$OUT/kube-score.txt"; then
  die "kube-score found issues"
fi
ok "kube-score: $(grep -c '\[OK\]' "$OUT/kube-score.txt") checks passed, no warnings or critical findings"
