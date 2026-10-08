# __APP_NAME__

Déploiement Kubernetes de **__APP_NAME__**, basé sur le
[chart Helm générique](https://github.com/ThomasSamson/generic-helm-chart)
(version du template : `__TEMPLATE_VERSION__`, voir `.template-version`).

- Image : `__IMAGE_REPOSITORY__`
- Release Helm : `__APP_NAME__` (préfixe de toutes les ressources : `__APP_NAME__-app`, `__APP_NAME__-worker`…)

## Environnements

| Environnement | Namespace | URL | Values |
|---|---|---|---|
| staging | `__APP_NAME__-staging` | https://__APP_NAME__.staging.example.com | `values/common.yaml` + `values/staging.yaml` |
| prod | `__APP_NAME__-prod` | https://__APP_NAME__.example.com | `values/common.yaml` + `values/prod.yaml` |

## Déployer

```bash
helm dependency build helm
helm upgrade --install __APP_NAME__ helm -n __APP_NAME__-<env> \
  -f values/common.yaml -f values/<env>.yaml
```

## Modifier la configuration

Toute la configuration du projet se trouve dans `values/` :

- `values/common.yaml` : commun à tous les environnements ;
- `values/<env>.yaml` : spécifique à un environnement.

Ne modifiez pas `helm/templates/` ni `helm/values.yaml` : ces fichiers viennent du template et
sont remplacés lors des mises à jour. La référence de toutes les options se trouve dans
`helm/values.yaml`, et la documentation du template dans [`docs/template.md`](docs/template.md).

Avant chaque modification, validez le rendu :

```bash
./scripts/test.sh
```

## Mettre à jour le template

```bash
./scripts/update-from-template.sh   # ou une ref précise : ./scripts/update-from-template.sh v1.2.0
git diff && ./scripts/test.sh
```

Dans le diff, vérifier que `helm/Chart.yaml` et `Chart.lock` ne reviennent pas à une version
de sous-chart plus ancienne que celle montée par Dependabot dans ce projet.

## Dependabot

`.github/dependabot.yml` suit les sous-charts de `helm/Chart.yaml`, les images tierces de
`values/*.yaml` (en version précise, pas `latest`) et les GitHub Actions
(voir [`docs/template.md`](docs/template.md#dependabot)).
