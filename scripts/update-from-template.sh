#!/usr/bin/env bash
# Récupère les évolutions du template dans un projet client.
# Seuls les fichiers « du template » sont remplacés (templates, values par défaut,
# dépendances, scripts, docs/template.md) ; le nom du chart, le README et les fichiers
# values/ du projet sont conservés.
# Usage : ./scripts/update-from-template.sh [ref]   (défaut : main)
set -euo pipefail

cd "$(dirname "$0")/.."

TEMPLATE_REPO="${TEMPLATE_REPO:-https://github.com/ThomasSamson/generic-helm-chart.git}"
ref="${1:-main}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git clone --quiet --depth 1 --branch "$ref" "$TEMPLATE_REPO" "$tmp"

name="$(grep '^name:' helm/Chart.yaml | awk '{print $2}')"

rm -rf helm/templates helm/ci
cp -r "$tmp/helm/templates" "$tmp/helm/ci" helm/
cp "$tmp/helm/values.yaml" "$tmp/helm/Chart.lock" helm/
cp "$tmp/scripts/"*.sh scripts/
mkdir -p docs
cp "$tmp/README.md" docs/template.md
sed "s/^name: generic-app$/name: ${name}/" "$tmp/helm/Chart.yaml" > helm/Chart.yaml
git -C "$tmp" rev-parse HEAD > .template-version

echo "Template mis à jour ($(cat .template-version)). Vérifier le diff puis lancer ./scripts/test.sh"
