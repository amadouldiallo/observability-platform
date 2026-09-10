# Observability & SRE Platform

Couche observabilité et fiabilité (SRE) pour la plateforme applicative des
Projets 1 et 2 — métriques, logs, traces, objectifs de fiabilité chiffrés
(SLI/SLO) et réponse à incident outillée (alerting + runbooks). Construite
en suivant
[Projet-3-Observability-SRE-Guide.md](Projet-3-Observability-SRE-Guide.md).

Ce dépôt est **séparé** de [Projet 1](https://github.com/amadouldiallo/gcp-platform)
et [Projet 2](https://github.com/amadouldiallo/gitops-platform) — son
propre code Terraform (`terraform/`), indépendant des modules des deux
autres dépôts. Mais contrairement au Projet 2 (qui provisionne son propre
cluster GKE), **ce projet ne crée aucun cluster** : il se déploie sur le
cluster `gitops-platform` déjà provisionné par le Projet 2. Voir
§Infrastructure pour le raisonnement complet.

## Comment lire ce dépôt

Mêmes symboles que les Projets 1 et 2 en tête de bloc de commentaire :

| Symbole | Signification |
|---|---|
| 🎯 | Le concept — ce que fait le composant, en langage simple |
| 🧠 | Analogie — pour ancrer le concept dans quelque chose de concret |
| ❓ | Pourquoi c'est important — la conséquence si on s'en passe |
| ⚠️ | Piège — une erreur facile à faire, rencontrée en écrivant ce code |
| 🔭 | Pour aller plus loin — une amélioration volontairement pas faite ici |

## Avancement

| Étape du guide | Dossier(s) | Statut |
|---|---|---|
| — Infrastructure (Terraform) | `terraform/` | ✅ **appliquée pour de vrai** — buckets GCS + Workload Identity actifs sur GCP, voir §Infrastructure |
| 1 — Métriques (Prometheus) | `k8s/monitoring/` | ⬜ à faire |
| 2 — Logs (Loki) | `k8s/loki/` | ⬜ à faire |
| 3 — Traces (OpenTelemetry + Tempo) | `k8s/tracing/` | ⬜ à faire |
| 4 — Golden Signals | `k8s/dashboards/` | ⬜ à faire |
| 5 — SLI | `docs/slo.md` | ⬜ à faire |
| 6 — SLO | `docs/slo.md` | ⬜ à faire |
| 7 — Alerting | `k8s/alerting/` | ⬜ à faire |
| 8 — Simulation d'incident | `docs/incident-drill.md` | ⬜ à faire |
| 9 — Runbooks | `docs/runbooks/` | ⬜ à faire |

## Infrastructure (Terraform)

`terraform/` ne provisionne **ni réseau ni cluster** — les deux existent
déjà (Projet 2). Il crée uniquement ce dont Loki et Tempo ont besoin pour
ne pas perdre leurs données au prochain remplacement de node : deux
buckets GCS dédiés (logs, traces) et les bindings Workload Identity qui
permettent à leurs pods d'y écrire sans clé JSON.

```mermaid
flowchart TD
    ENV["📁 environments/dev"] --> STO["📦 module storage<br/>2 buckets GCS + Workload Identity"]
    STO --> LB["🪣 loki-chunks<br/>rétention 14 j"]
    STO --> TB["🪣 tempo-traces<br/>rétention 7 j"]
    LB -.->|"iam.workloadIdentityUser"| LKSA["ServiceAccount K8s<br/>loki/loki"]
    TB -.->|"iam.workloadIdentityUser"| TKSA["ServiceAccount K8s<br/>tracing/tempo"]

    style STO fill:#4285F4,color:#fff
```

❓ **Pourquoi GCS et pas un simple PVC** : ce même cluster a déjà perdu la
configuration de Vault (Projet 2, Étape 7) lors d'un remplacement de node
pool — les données sur disque local d'un pod ne survivent pas au
déplacement de ce pod vers un autre node. Un bucket GCS, lui, existe
indépendamment du cycle de vie des pods et des nodes.

⚠️ **Piège anticipé** : le nom du ServiceAccount Kubernetes attendu par le
binding Workload Identity (`loki/loki`, `tracing/tempo`) doit correspondre
exactement à celui créé par le chart Helm — vérifié via
`kubectl get sa -n <namespace>` avant d'annoter, pas supposé.

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars   # project_id (celui du cluster gitops-platform)
cp backend.hcl.example backend.hcl             # même bucket de state que les Projets 1/2
terraform init -backend-config=backend.hcl
terraform plan     # 11 to add, 0 to change, 0 to destroy — testé contre un vrai projet GCP
terraform apply
```

⚠️ **Ces buckets sont actuellement appliqués et actifs**
(`devops-498817-loki-chunks`, `devops-498817-tempo-traces`,
europe-west1) — coût marginal (stockage seul, purge automatique à 14/7
jours) mais réel. `terraform destroy` depuis
`terraform/environments/dev` les supprime proprement.

---

*Les sections suivantes (§Métriques, §Logs, §Traces, §Golden Signals,
§SLI/SLO, §Alerting, §Simulation d'incident, §Runbooks) seront ajoutées au
fil de l'avancement réel, chacune testée sur le cluster avant d'être
documentée — même discipline que les Projets 1 et 2.*
