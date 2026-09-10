# Runbook — HighLatency

**Alerte** : `HighLatency` — p95 de latence > 500ms sur 5 minutes,
namespace `task-tracker`.

## Symptômes observés

- Alertmanager / Prometheus : `HighLatency` en `firing`.
- Dashboard Golden Signals (Grafana) : panel "Latency" (p95/p99) élevé.
- Utilisateurs : l'application répond lentement, sans forcément d'erreur.

## Diagnostic immédiat

```promql
# p95 par handler — isoler QUELLE route est lente, pas juste "l'API"
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{namespace="task-tracker"}[5m])) by (le, handler))

# Saturation CPU/mémoire du pod (voir dashboard Golden Signals, panel Saturation)
100 * sum(rate(container_cpu_usage_seconds_total{namespace="task-tracker",container="backend"}[5m])) / sum(kube_pod_container_resource_limits{namespace="task-tracker",container="backend",resource="cpu"})
```

Depuis Grafana Explore (datasource Tempo) : chercher une trace récente et
lente (`durationMs` élevé dans la liste de recherche), ouvrir son détail
— le span enfant `SELECT` (voir Étape 3) révèle si le temps est passé
côté requête SQL ou ailleurs dans le code applicatif.

```bash
# Le pool de connexions Postgres est petit par conception (voir
# apps/backend/app/db.py, dépôt gitops-platform) : min_size=1, max_size=5
# — sous forte charge concurrente, des requêtes peuvent ATTENDRE une
# connexion libre plutôt qu'échouer, ce qui se traduit par de la
# LATENCE, pas des erreurs. Vérifier le nombre de connexions actives :
kubectl exec -n task-tracker deploy/task-tracker-db -- \
  psql -U appuser -d appdb -c "SELECT count(*) FROM pg_stat_activity;"
```

## Actions de remédiation (par ordre de priorité)

1. **Isoler la route lente** (requête par handler ci-dessus) — une seule
   route lente pointe vers une requête SQL spécifique à optimiser
   (index manquant, `ORDER BY` sans index sur une grosse table...) ;
   toutes les routes lentes en même temps pointent plutôt vers une
   ressource partagée (CPU, pool DB).
2. **Vérifier la saturation CPU** (panel Saturation) — un CPU proche de
   sa limite (`throttling`) ralentit TOUT le pod, pas une route précise.
3. **Vérifier l'épuisement du pool de connexions DB** (ci-dessus) — si
   `pg_stat_activity` approche `max_size=5`, les requêtes font la queue.
4. Si confirmé, augmenter `backend.resources.limits.cpu` (chart Helm) ou
   `max_size` du pool (`apps/backend/app/db.py`) est une vraie option de
   remédiation, mais AUGMENTER LA CAPACITÉ NE DEVRAIT JAMAIS ÊTRE LE
   PREMIER RÉFLEXE (voir la leçon FinOps des Étapes 1/2 de ce projet) —
   confirmer la cause avant de dépenser plus.

## Critère de résolution

`HighLatency` repasse `inactive` de lui-même dès que le p95 reste sous
500ms pendant 5 minutes.
