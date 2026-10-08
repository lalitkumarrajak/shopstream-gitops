#!/usr/bin/env bash
# Promotes the image tag currently running in dev to prod (commit + open a PR).
# Prod is manually synced in Argo CD after the PR is reviewed and merged.
source "$(dirname "$0")/lib.sh"
TAG="${1:-$(dev_image_tag)}"
[[ "$TAG" == "latest" ]] && die "refusing to promote the mutable 'latest' tag — pass a git SHA"
file="$ROOT_DIR/environments/prod/values.yaml"
awk -v tag="$TAG" '/^global:/{g=1} g&&/^  image:/{i=1} g&&i&&/^    tag:/{sub(/tag:.*/, "tag: " tag); g=0; i=0} {print}' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
git -C "$ROOT_DIR" switch -c "promote/prod-${TAG:0:7}"
git -C "$ROOT_DIR" commit -am "chore(prod): promote shopstream ${TAG:0:7}"
if command -v gh >/dev/null; then
  gh pr create --title "Promote ShopStream ${TAG:0:7} to prod" \
    --body "Promotes \`$TAG\` (green in dev) to prod. Sync \`shopstream-prod\` in Argo CD after merge."
fi
