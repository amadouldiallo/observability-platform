# Runbook — HighErrorRate

**Alerte** : `HighErrorRate` — taux d'erreur 5xx > 1% sur 5 minutes,
namespace `task-tracker`.

## Symptômes observés

- Alertmanager / Prometheus : `HighErrorRate` en `firing`.
- Dashboard Golden Signals (Grafana) : panel "Errors" au-dessus de 1%.
- Utilisateurs : erreurs 500 sur `https://.../api/tasks`.

## Diagnostic immédiat

```promql
# Quel(s) handler(s) sont en erreur — pas juste "combien"
sum by (handler) (rate(http_requests_total{namespace="task-tracker",status="5xx"}[5m]))
```

```bash
# Logs récents du backend (Loki) — chercher les tracebacks
# via Grafana Explore, datasource Loki :
{namespace="task-tracker",app="backend"} |= "Traceback"

# État des pods
kubectl get pods -n task-tracker -l app.kubernetes.io/name=backend

# La base est-elle joignable (readyz ne dépend QUE de ça) ?
kubectl exec -n task-tracker deploy/task-tracker-backend -- \
  python -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8000/readyz').status)"
```

Depuis une trace Tempo (Grafana Explore, datasource Tempo, filtrer sur
une trace récente en erreur) : le span en échec porte
`status: {code: ERROR}` — identifie précisément où (HTTP handler vs
requête SQL) l'erreur a été levée.

## Actions de remédiation (par ordre de priorité)

1. **La base est-elle joignable ?** (`/readyz` ci-dessus) — si non, c'est
   un incident Postgres, pas un bug applicatif. Vérifier
   `kubectl get pods -n task-tracker -l app.kubernetes.io/name=db`.
2. **Un déploiement récent ?** `kubectl rollout history deployment/task-tracker-backend -n task-tracker`
   — si les erreurs ont commencé juste après un `git push` sur
   `gitops-platform`, c'est le suspect n°1. `kubectl rollout undo` en
   dernier recours (Argo CD resynchronisera à la prochaine réconciliation
   sauf si `syncPolicy.automated` est désactivée — voir runbook
   `backend-down.md` pour ce piège).
3. **External Secrets / Vault** : un mot de passe Postgres qui n'a pas pu
   se synchroniser produirait des 5xx sur toute requête DB — vérifier
   `kubectl get externalsecret -n task-tracker`.
4. Si rien de tout ça, inspecter directement la trace Tempo de la
   requête en échec pour la stack complète.

## Critère de résolution

`HighErrorRate` repasse `inactive` de lui-même dès que le taux d'erreur
reste sous 1% pendant 5 minutes — pas d'action manuelle pour "fermer"
l'alerte, juste corriger la cause.
