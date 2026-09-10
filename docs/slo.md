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

*Les SLO (objectifs chiffrés sur ces SLI) et le calcul de l'error budget
seront ajoutés à l'Étape 6.*
