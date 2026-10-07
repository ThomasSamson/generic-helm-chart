#!/usr/bin/env bash
# Valide le chart : lint + rendu + kubeconform pour chaque scénario.
# Scénarios : helm/ci/*.yaml (template) et values/<env>.yaml combinés à values/common.yaml (projet).
# Usage : ./scripts/test.sh
set -euo pipefail

cd "$(dirname "$0")/.."

K8S_VERSION="${K8S_VERSION:-1.31.0}"
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

# Déclare les dépôts des dépendances (requis par `helm dependency build`).
i=0
for repo in $(awk '/repository:/ {print $2}' helm/Chart.yaml); do
  helm repo add "dep-$((i++))" "$repo" --force-update >/dev/null
done
helm dependency build helm >/dev/null

run() {
  local label="$1"; shift
  echo "── ${label}"
  helm lint helm --quiet "$@"
  helm template test helm --namespace test "$@" \
    | kubeconform -strict -summary -kubernetes-version "$K8S_VERSION" \
        -schema-location default -schema-location "$CRD_SCHEMAS"
}

for f in helm/ci/*.yaml; do
  run "$f" -f "$f"
done

for f in values/*.yaml; do
  [[ "$(basename "$f")" == common.yaml ]] && continue
  grep -q '__APP_NAME__' "$f" && continue  # template non initialisé
  run "values/common.yaml + $f" -f values/common.yaml -f "$f"
done
