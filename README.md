# Chart Helm générique Les Tilleuls

Repo template pour déployer n'importe quelle application conteneurisée (API Symfony/FrankenPHP,
PWA, workers, cronjobs…) sans écrire de template Helm : **un projet ne modifie que des fichiers values**.

## Démarrer un projet client

```bash
# 1. Créer le repo du client à partir de ce template (GitHub « Use this template »), puis :
./scripts/init.sh mon-app registry.example.com/mon-app/api

# 2. Compléter values/common.yaml, values/staging.yaml, values/prod.yaml

# 3. Valider
./scripts/test.sh

# 4. Déployer (le nom de la release = préfixe de toutes les ressources)
helm dependency build helm
helm upgrade --install mon-app helm -n mon-app-prod \
  -f values/common.yaml -f values/prod.yaml
```

`init.sh` renomme le chart (labels `app.kubernetes.io/name`) et remplit les fichiers `values/`.
Les ressources sont nommées `<release>-<clé>` : `mon-app-app`, `mon-app-worker`,
`mon-app-cnpg`…

## Organisation

| Chemin | Rôle | Modifié par le projet ? |
|---|---|---|
| `helm/templates/` | Templates génériques | **Non** |
| `helm/values.yaml` | Valeurs par défaut + référence documentée de toutes les options | **Non** |
| `helm/ci/` | Scénarios de test du template | Non |
| `helm/Chart.yaml` | Nom du chart (via `init.sh`), dépendances | Nom uniquement |
| `values/*.yaml` | Configuration du projet, par environnement | **Oui** |
| `scripts/` | `init.sh`, `test.sh`, `update-from-template.sh` | Non |

Comme les projets ne touchent pas aux templates, on peut les mettre à jour quand le template évolue :

```bash
./scripts/update-from-template.sh          # ou une ref : v1.2.0
git diff && ./scripts/test.sh
```

Une fonctionnalité qui manque doit être ajoutée **dans le template**, pas dans le projet.
En attendant, `extraObjects` permet d'ajouter n'importe quel manifeste.

## Fonctionnalités

Toutes les options sont décrites dans [`helm/values.yaml`](helm/values.yaml).

| Fonctionnalité | Clé | Notes |
|---|---|---|
| Image par défaut | `image` | Surchargeable par workload (`deployments.pwa.image.repository`) |
| Deployments (app, PWA, workers…) | `deployments.<nom>` | Autant que nécessaire ; `enabled` pour les (dés)activer |
| CronJobs | `cronJobs.<nom>` | `schedule`, `timeZone`, `concurrencyPolicy`… |
| Jobs (migrations, fixtures) | `jobs.<nom>` | En hook Helm (`helmHook`) ou recréés à chaque révision |
| Valeurs communes aux workloads | `defaults` | Ressources, securityContext, affinités… |
| Variables d'env | `env` (map), `extraEnv`, `envFrom` | Globales + par workload ; `null` retire une clé |
| Secrets | `secretEnv`, `existingSecrets` | `existingSecrets` en production |
| Fichiers de config | `configFiles` | Montés en subPath, ciblage par workload |
| Volumes persistants | `persistence` | PVC créé ou `existingClaim` |
| Service, HPA/KEDA, PDB, PodMonitor | `deployments.<nom>.service/autoscaling/pdb/monitoring` | |
| Ingress | `ingresses.<nom>` | Plusieurs ingress possibles |
| HTTPRoute (Gateway API) | `httpRoutes.<nom>` | Raccourci `backend`, redirection HTTPS |
| Basic auth (« htaccess ») | `basicAuth` | Middleware Traefik appliqué aux ingress/routes |
| Non-indexation (hors prod) | `noIndex` | En-tête `X-Robots-Tag` ajouté par Traefik ; activé dans `values/staging.yaml` |
| NetworkPolicy | `networkPolicy` | Pods de la release |
| NetworkPolicy CNPG | `networkPolicy.cnpg` | Automatique si `networkPolicy.enabled` et `addons.cnpg.enabled` : instances (5432 depuis la release, les poolers et le cluster ; 8000 depuis l'opérateur ; 9187 si `metricsNamespace`) et poolers ; egress 5432 ajouté à la policy de la release si elle a `Egress`. Requise avec le default-deny Ingress+Egress posé par Kyverno sur nos namespaces |
| ServiceAccount, RBAC | `serviceAccount`, `rbac` | |
| Manifestes libres | `extraObjects` | Passent par `tpl` |

### Dépendances

Elles s'activent avec `addons.<nom>.enabled`, et chaque sous-chart se configure sous la clé `<nom>:`.
Les variables de connexion sont injectées automatiquement dans tous les workloads
(désactivable via `addons.<nom>.injectEnv.enabled`, ou en redéfinissant la variable dans `env`).

| Addon | Chart | Variables injectées |
|---|---|---|
| `cnpg` | [cloudnative-pg/cluster](https://github.com/cloudnative-pg/charts) | `DATABASE_URL`, `DATABASE_USER`, `DATABASE_PASSWORD` |
| `valkey` | [valkey-io/valkey-helm](https://github.com/valkey-io/valkey-helm) | `REDIS_URL` |
| `mercure` | [dunglas/mercure](https://github.com/dunglas/mercure/tree/main/charts/mercure) | `MERCURE_URL`, `MERCURE_JWT_SECRET` |
| `meilisearch` | [meilisearch-kubernetes](https://github.com/meilisearch/meilisearch-kubernetes) | `MEILISEARCH_URL` |
| `maildev` | [pando85/helm-maildev](https://github.com/pando85/helm-maildev) | `MAILER_DSN` |

> Pourquoi `addons.mercure.enabled` et pas `mercure.enabled` ? Le sous-chart mercure a un schéma
> JSON strict qui refuse toute clé inconnue. Toutes les dépendances suivent donc la même règle.

### Ajouter une dépendance au template

1. Déclarer le chart dans `helm/Chart.yaml` avec `condition: addons.<nom>.enabled`.
2. Ajouter `addons.<nom>` et `<nom>: {}` dans `helm/values.yaml`.
3. Si besoin, injecter ses variables dans `tilleuls.autoEnv` (`helm/templates/_helpers.tpl`).
4. Activer la dépendance dans `helm/ci/full-values.yaml`, puis lancer `./scripts/test.sh`.

## Exemples

### Worker Messenger + cron

```yaml
deployments:
  worker:
    enabled: true
    replicaCount: 2
    command: [php, bin/console, messenger:consume, async, --time-limit=3600]

cronJobs:
  purge:
    enabled: true
    schedule: "0 3 * * *"
    timeZone: Europe/Paris
    command: [php, bin/console, app:purge]
```

### API + PWA derrière une HTTPRoute protégée par mot de passe

```yaml
deployments:
  pwa:
    enabled: true
    image:
      repository: registry.example.com/mon-app/pwa
    ports:
      - name: http
        containerPort: 3000
    service:
      enabled: true
      ports: [{name: http, port: 80, targetPort: http}]

httpRoutes:
  main:
    enabled: true
    hostnames: [mon-app.example.com]
    rules:
      - matches: [{path: {type: PathPrefix, value: /api}}]
        backend: {service: app, port: 80}
      - matches: [{path: {type: PathPrefix, value: /webhooks}}]
        basicAuth: false            # pas d'auth pour les webhooks
        backend: {service: app, port: 80}
      - matches: [{path: {type: PathPrefix, value: /}}]
        backend: {service: pwa, port: 80}

basicAuth:
  enabled: true
  existingSecret: mon-app-basicauth  # clé « users » au format htpasswd
```

### Migrations Doctrine en hook

```yaml
jobs:
  migrations:
    enabled: true
    command: [php, bin/console, doctrine:migrations:migrate, --no-interaction]
    helmHook:
      enabled: true
      hooks: post-install,pre-upgrade
```

### PostgreSQL avec pooler et sauvegardes S3

```yaml
addons:
  cnpg:
    enabled: true
    injectEnv:
      pooler: rw
      query: "?serverVersion=16&charset=utf8"

cnpg:
  cluster:
    instances: 2
    plugins:
      - name: barman-cloud.cloudnative-pg.io
        isWALArchiver: true
  backups:
    enabled: true
    endpointURL: https://s3.fr-par.scw.cloud
    destinationPath: s3://backups/mon-app/
  poolers:
    - name: rw
      type: rw
      poolMode: transaction
      instances: 1
```

## Règles de fonctionnement

- **Fusion avec `defaults`** : une clé de premier niveau définie dans un workload remplace
  *entièrement* celle de `defaults`, sans fusion profonde. Par exemple, `resources` dans
  `deployments.worker` remplace toutes les ressources par défaut.
- **`env` en map** : se fusionne naturellement entre `common.yaml` et `<env>.yaml`. Les clés sont
  triées : pour utiliser `$(VAR)`, passer par `extraEnv` (liste ordonnée).
- **`tpl`** : les valeurs de `env`, les hosts, les annotations, `extraObjects`… acceptent la
  syntaxe Helm (`{{ .Release.Name }}`).
- **Prérequis du cluster**, selon les fonctionnalités activées : opérateur CNPG et plugin
  barman-cloud, KEDA, Prometheus Operator, Traefik (basic auth), Gateway API.
