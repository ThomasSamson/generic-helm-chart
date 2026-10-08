#!/usr/bin/env bash
# Initialise un projet client à partir du template.
# Usage : ./scripts/init.sh [--no-dependabot] <nom-app> [repository-image]
#   ./scripts/init.sh mon-app registry.example.com/mon-app/api
set -euo pipefail

cd "$(dirname "$0")/.."

dependabot=true
args=()
for arg in "$@"; do
  case "$arg" in
    --no-dependabot) dependabot=false ;;
    -*) echo "Option inconnue : $arg" >&2; exit 1 ;;
    *) args+=("$arg") ;;
  esac
done

name="${args[0]:-}"
image="${args[1]:-}"

if [[ ! "$name" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || (( ${#name} > 40 )); then
  echo "Nom invalide : '$name' (minuscules, chiffres et tirets, 40 caractères max)." >&2
  exit 1
fi

if ! grep -q '^name: generic-app$' helm/Chart.yaml; then
  echo "Le chart a déjà été initialisé ($(grep '^name:' helm/Chart.yaml))." >&2
  exit 1
fi

# Nom du chart : apparaît dans les labels app.kubernetes.io/name et helm.sh/chart.
sed -i.bak "s/^name: generic-app$/name: ${name}/" helm/Chart.yaml && rm helm/Chart.yaml.bak

# Fichiers de values du projet (le helm/values.yaml du template n'est jamais modifié).
for f in values/*.yaml; do
  sed -i.bak "s/__APP_NAME__/${name}/g" "$f" && rm "$f.bak"
  if [[ -n "$image" ]]; then
    sed -i.bak "s|__IMAGE_REPOSITORY__|${image}|g" "$f" && rm "$f.bak"
  fi
done

# Version du template utilisée, pour les mises à jour ultérieures.
git rev-parse HEAD > .template-version 2>/dev/null || echo "unknown" > .template-version
version="$(cut -c1-7 .template-version)"

# README : la doc du template passe dans docs/, le README devient celui du projet.
mkdir -p docs
mv README.md docs/template.md
sed -e "s/__APP_NAME__/${name}/g" \
    -e "s|__IMAGE_REPOSITORY__|${image:-à renseigner dans values/common.yaml}|g" \
    -e "s/__TEMPLATE_VERSION__/${version}/g" \
    .template/README.md.tpl > README.md

# Dependabot : la config du template (sous-charts) est remplacée par celle du projet
# (images de values/, GitHub Actions), ou supprimée avec --no-dependabot.
if [[ "$dependabot" == true ]]; then
  cp .template/dependabot.yml .github/dependabot.yml
else
  rm -f .github/dependabot.yml
fi
rm -rf .template

cat <<MSG
Projet initialisé : ${name}

Prochaines étapes :
  1. Compléter values/common.yaml, values/staging.yaml et values/prod.yaml
  2. Tester le rendu :  ./scripts/test.sh
  3. Déployer :
       helm dependency build helm
       helm upgrade --install ${name} helm -n <namespace> \\
         -f values/common.yaml -f values/<env>.yaml
MSG
