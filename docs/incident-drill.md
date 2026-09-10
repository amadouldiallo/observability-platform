# Simulation d'incident — backend task-tracker

**Objectif** : vérifier que la chaîne complète (détection → alerte →
dashboard → runbook) fonctionne réellement, en provoquant une vraie
panne — pas en supposant qu'elle marcherait.

**Scénario prévu par le guide** : `kubectl scale deployment backend
--replicas=0`, puis mesurer les délais réels jusqu'au retour à la
normale.

## Tentative n°1 — annulée en ~3 secondes par Argo CD

```
19:00:58Z  kubectl scale --replicas=0
19:00:58Z  (événement K8s) ScalingReplicaSet : 1 -> 0
19:01:01Z  (événement K8s) ScalingReplicaSet : 0 -> 1  <- Argo CD selfHeal
```

**Ce qui s'est passé** : Argo CD (Projet 2, Étape 6) surveille en continu
l'écart entre l'état déclaré (`charts/app` sur `main`,
`backend.replicaCount: 1`) et l'état réel du cluster —
`syncPolicy.automated.selfHeal: true`. Un `kubectl scale` manuel EST
exactement le type d'écart que selfHeal corrige, en l'occurrence en **~3
secondes**, bien plus vite qu'aucune alerte humaine n'aurait pu réagir.

**Conséquence pour la suite du drill** : sur un cluster piloté par
GitOps, on ne peut pas simuler une panne avec un simple `kubectl scale`
sans d'abord neutraliser la réconciliation automatique — sans quoi on ne
mesure pas une panne, on mesure la vitesse du self-heal (qui est,
accessoirement, une donnée intéressante en soi : 3 secondes de MTTR pour
ce type de dérive précis, sans aucune intervention humaine).

## Tentative n°2 — la vraie simulation

Automatisation Argo CD désactivée manuellement au préalable :
```bash
kubectl patch application task-tracker -n argocd --type merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'
```

| Heure (UTC) | Δ depuis T0 | Événement |
|---|---|---|
| 19:00:58 | T+0s | `kubectl scale --replicas=0` |
| 19:01:01 | T+3s | Pod supprimé ; `curl` public renvoie déjà `503` |
| ~19:01:35 | ~T+37s | Confirmé : la cible `task-tracker-backend` a **disparu** de `/api/v1/targets` (pas `up=0`, absence totale — voir ⚠️ ci-dessous) |
| — | — | Les 4 alertes existantes (Étape 7) : **aucune ne bouge**, `state: inactive` pour toutes |
| — | — | *(à ce point, ajout de l'alerte `BackendDown` — voir plus bas)* |
| 19:03:47 | T+2m49s | `BackendDown` passe `inactive` → `pending` |
| 19:05:54 | T+4m56s | `BackendDown` passe `pending` → **`firing`** (délai `for: 2m` de la règle + ~7s de cycle d'évaluation) |
| 19:06:13 | — | `kubectl scale --replicas=1` + réactivation `selfHeal` |
| 19:06:37 | +24s | Pod `1/1 Running` ; `curl` public renvoie `200` |
| ~19:07:00 | +~45s | `up{job="task-tracker-backend"}` réapparaît (`1`) ; `BackendDown` repasse `inactive` tout seul |

## ⚠️ Le vrai trou de couverture découvert

Aucune des 4 alertes de l'Étape 7 (`HighErrorRate`, `HighLatency`,
`TaskTrackerPodCrashLooping`, `SLOViolation`) ne s'est déclenchée pendant
la panne — **c'est exactement le genre de chose qu'on ne peut pas deviner
en lisant du YAML**, la valeur réelle de cette étape.

**Root cause** : les 3 premières dépendent toutes de métriques ÉMISES PAR
L'APPLICATION elle-même (`http_requests_total`,
`http_request_duration_seconds_*`). Un backend totalement arrêté ne peut,
par définition, plus rien émettre sur son propre état — les requêtes
PromQL ne renvoient pas "0" ou "faux", elles ne renvoient AUCUNE donnée,
et une règle d'alerte sans donnée reste `inactive` indéfiniment, même en
pleine panne totale. `TaskTrackerPodCrashLooping`, elle, cible
spécifiquement `CrashLoopBackOff` — un déploiement volontairement scalé à
0 n'est pas en boucle de crash, il n'a simplement plus aucun pod.

**Second détail découvert en creusant** : `up{job="task-tracker-backend"}
== 0` (le réflexe naturel) n'aurait pas marché non plus. Une fois le
dernier pod parti, Kubernetes retire l'Endpoint du Service, et le Service
Discovery de Prometheus retire la cible elle-même de sa liste active — la
série `up` ne passe pas à `0`, elle **disparaît purement et simplement**
(vérifié : `up{job="task-tracker-backend"}` renvoyait `[]`, pas
`[{"value":[...,"0"]}]`). Seule la fonction `absent()` détecte cette
disparition — la nuance entre "la cible répond mal" (`up == 0`) et "la
cible n'existe plus" (`absent(up{...})`) n'est pas cosmétique, ce sont
deux mécanismes de détection différents pour deux pannes différentes.

**Fixé pendant le drill, pas après** : ajout de l'alerte `BackendDown`
(`absent(up{job="task-tracker-backend"})`, `for: 2m`) à
`k8s/alerting/prometheusrules.yaml` — puis vérifié EN DIRECT, panne
toujours active, qu'elle passe bien `pending` → `firing` (voir tableau
ci-dessus), avant même de restaurer le service.

## MTTD / MTTR observés

- **MTTD** (temps jusqu'à détection actionnable) : ~4min56s — dominé
  presque entièrement par le `for: 2m` volontairement choisi (éviter de
  sonner sur un redémarrage de routine) + le temps qu'il a fallu pour
  d'abord DÉCOUVRIR qu'aucune alerte existante ne captait ce scénario, et
  en écrire une nouvelle. Sur une alerte déjà en place et correctement
  conçue, ce délai se réduirait au seul `for:` choisi.
- **MTTR** (temps de rétablissement une fois la décision prise) : 24
  secondes (`kubectl scale` → pod `Ready`), résolution de l'alerte
  quasi-immédiate ensuite.

Ces deux chiffres mesurent des choses différentes — réduire l'un
(détection plus rapide) ne réduit pas forcément l'autre (temps de
remédiation), exactement la distinction que fait la littérature SRE entre
les deux métriques.
