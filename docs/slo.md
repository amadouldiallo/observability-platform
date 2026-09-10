# SLI / SLO — backend task-tracker

## SLI (Service Level Indicators)

Un SLI est une formule PromQL précise, sans jugement de valeur — juste "ce
qu'on mesure". Les 3 SLI ci-dessous excluent volontairement le handler
`/metrics` (scrape Prometheus, pas trafic utilisateur) — `/healthz` et
`/readyz` ne peuvent pas apparaître dans `http_requests_total` : ils sont
déjà exclus à la source par `excluded_handlers` dans l'instrumentation
(voir `apps/backend/app/main.py`, dépôt gitops-platform).

### 1. Disponibilité — proportion de requêtes réussies (2xx/3xx)

```promql
sum(rate(http_requests_total{namespace="task-tracker",handler!~"/metrics",status=~"2xx|3xx"}[5m]))
/
sum(rate(http_requests_total{namespace="task-tracker",handler!~"/metrics"}[5m]))
```

**Vérifié réellement** : `1` (100%) sur du trafic généré en direct
(`curl .../api/tasks`, toutes réponses 2xx).

### 2. Taux d'erreur — proportion de réponses 5xx

```promql
sum(rate(http_requests_total{namespace="task-tracker",handler!~"/metrics",status="5xx"}[5m]))
/
sum(rate(http_requests_total{namespace="task-tracker",handler!~"/metrics"}[5m]))
```

**Vérifié réellement** : aucune donnée tant qu'aucune erreur 5xx ne s'est
produite (comportement PromQL correct — un vecteur vide au numérateur ne
produit aucun résultat, pas un zéro trompeur) — la première viendra de la
simulation d'incident (Étape 8).

### 3. Latence — proportion de requêtes sous 300ms

```promql
sum(rate(http_request_duration_seconds_bucket{namespace="task-tracker",handler!~"/metrics",le="0.3"}[5m]))
/
sum(rate(http_request_duration_seconds_count{namespace="task-tracker",handler!~"/metrics"}[5m]))
```

⚠️ **Piège rencontré pour de vrai** : les bornes d'histogramme par défaut
de `prometheus-fastapi-instrumentator` sont `(0.1, 0.5, 1)` secondes —
aucune borne exactement à 0.3s. Un histogramme Prometheus ne peut mesurer
QUE les seuils qui correspondent à une de ses bornes (`le=...`) ; sans
borne à 0.3, cette requête aurait silencieusement renvoyé une valeur
fausse (ou aucune donnée). Fixé en ajoutant `0.3` aux bornes personnalisées
du backend (voir `metrics.default(latency_lowr_buckets=(0.1, 0.3, 0.5, 1))`
dans `apps/backend/app/main.py`, dépôt gitops-platform) — **le choix des
bornes d'un histogramme doit être aligné sur les seuils qu'on veut
réellement mesurer**, pas laissé aux valeurs par défaut d'une librairie.

**Vérifié réellement** : `1` (100% des requêtes sous 300ms) sur du trafic
généré en direct — cohérent avec le p95 observé au dashboard Golden
Signals (~95ms, Étape 4).

⚠️ **Note de test rencontrée en vérifiant ces requêtes** : interrogées
immédiatement après une rafale de trafic très courte (quelques requêtes
en une fraction de seconde), SLI 1 et SLI 3 ont renvoyé `NaN` — pas un bug
des formules, mais `rate()` sur une fenêtre de 5 minutes a besoin d'au
moins deux points de scrape (15s d'intervalle, voir le ServiceMonitor de
l'Étape 1) pour extrapoler un débit ; interrogé trop tôt après une rafale
isolée, `0/0 = NaN`. Reproduit avec un trafic continu sur quelques
secondes de plus : `NaN` disparaît, remplacé par la vraie valeur.

---

## SLO (Service Level Objectives)

Un SLO est un SEUIL chiffré appliqué à un SLI, sur une période donnée — ce
qui distingue "le service va bien" (une opinion) de "le service respecte
99,9% de disponibilité sur 30 jours" (un fait vérifiable).

| SLI | SLO | Période |
|---|---|---|
| Disponibilité | ≥ 99,9 % | 30 jours glissants |
| Taux d'erreur | < 0,1 % | 30 jours glissants |
| Latence (p95) | < 300 ms | 30 jours glissants |

### Error budget

99,9% de disponibilité sur 30 jours tolère au maximum :

```
(1 − 0,999) × 30 jours × 24 h × 60 min = 43,2 minutes d'indisponibilité par mois
```

Tant que ce budget n'est pas épuisé, l'équipe peut prendre des risques
(déployer plus vite, itérer) ; une fois épuisé, priorité à la stabilité —
voir l'Étape 7 (Alerting), qui déclenche précisément sur ce seuil.

### Requêtes PromQL — version "manuel" (fenêtre 30 jours, conforme au SLO)

```promql
# Disponibilité sur 30j
sum(rate(http_requests_total{namespace="task-tracker",handler!~"/metrics",status=~"2xx|3xx"}[30d]))
/
sum(rate(http_requests_total{namespace="task-tracker",handler!~"/metrics"}[30d]))

# % d'error budget consommé (99,9% de SLO -> budget d'erreur de 0,1%)
(
  1 - (
    sum(rate(http_requests_total{namespace="task-tracker",handler!~"/metrics",status=~"2xx|3xx"}[30d]))
    /
    sum(rate(http_requests_total{namespace="task-tracker",handler!~"/metrics"}[30d]))
  )
) / (1 - 0.999) * 100
```

⚠️ **Piège rencontré pour de vrai en testant ces requêtes sur CE cluster** :
elles s'exécutent sans la moindre erreur et renvoient un résultat —
`1` (100%), en apparence parfait. Mais le Prometheus de ce lab a une
rétention de **6 heures seulement** (`retention: 6h`, voir
`k8s/monitoring/values.yaml`, Étape 1 — une décision FinOps délibérée :
Prometheus n'est pas la source de vérité long terme de ce projet). Une
fenêtre `[30d]` sur un Prometheus qui n'a JAMAIS retenu 30 jours de
données ne produit pas une erreur — elle calcule silencieusement sur les
seules données réellement disponibles (au mieux 6h), tout en prétendant
représenter 30 jours. Vérifié en interrogeant directement l'API
`/api/v1/status/runtimeinfo` : `storageRetention: "6h"`, confirmé.

🔭 **Pour aller plus loin** (délibérément hors scope ici) : un vrai SLO à
30 jours demande un stockage long terme (Thanos, Mimir, ou un
`remote_write` vers un service managé) — Prometheus local n'est fait que
pour l'exploitation à court terme, pas l'historique.

### Requêtes PromQL — version utilisée sur CE cluster (fenêtre 1h, adaptée à la rétention réelle)

Pour que l'alerting de l'Étape 7 fonctionne réellement sur ce lab (pas
seulement "en théorie"), les mêmes formules sont utilisées avec une
fenêtre d'1h — documentée comme une adaptation de lab, pas le SLO réel :

```promql
# Disponibilité (fenêtre 1h)
sum(rate(http_requests_total{namespace="task-tracker",handler!~"/metrics",status=~"2xx|3xx"}[1h]))
/
sum(rate(http_requests_total{namespace="task-tracker",handler!~"/metrics"}[1h]))

# % d'error budget consommé (fenêtre 1h)
(
  1 - (
    sum(rate(http_requests_total{namespace="task-tracker",handler!~"/metrics",status=~"2xx|3xx"}[1h]))
    /
    sum(rate(http_requests_total{namespace="task-tracker",handler!~"/metrics"}[1h]))
  )
) / (1 - 0.999) * 100

# Latence p95 < 300ms (fenêtre 1h) — utilisable directement comme condition d'alerte
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{namespace="task-tracker",handler!~"/metrics"}[1h])) by (le)) < 0.3
```

**Vérifié réellement** : les 3 requêtes ci-dessus exécutées contre le vrai
Prometheus — error budget consommé `0` (aucune erreur), latence p95
`0.095` (< 0.3, condition vraie).
