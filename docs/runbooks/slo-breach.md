# Runbook — SLOViolation

**Alerte** : `SLOViolation` — plus de 80% de l'error budget (SLO 99,9%
de disponibilité) consommé sur la fenêtre observée (voir
[docs/slo.md](../slo.md) pour la fenêtre réellement utilisée sur ce
cluster, et pourquoi elle diffère des 30 jours "manuel").

## Symptômes observés

- Alertmanager / Prometheus : `SLOViolation` en `firing`.
- **C'est presque toujours un symptôme, pas une cause** — cette alerte
  agrège les mêmes données que `HighErrorRate`/`HighLatency` sur une
  fenêtre plus large ; si elle sonne, l'une des deux (ou `BackendDown`)
  a très probablement déjà sonné, ou est sur le point de le faire.

## Diagnostic immédiat

```promql
# % d'error budget consommé, là, maintenant
(
  1 - (
    sum(rate(http_requests_total{namespace="task-tracker",handler!~"/metrics",status=~"2xx|3xx"}[1h]))
    /
    sum(rate(http_requests_total{namespace="task-tracker",handler!~"/metrics"}[1h]))
  )
) / (1 - 0.999) * 100
```

1. Vérifier dans Alertmanager si `HighErrorRate`, `HighLatency` ou
   `BackendDown` sont ACTIVES en parallèle — si oui, suivre LEUR runbook
   d'abord, celui-ci ne fait que confirmer l'impact cumulé.
2. Si aucune des 3 n'est active mais que `SLOViolation` l'est quand même :
   une succession de PETITS incidents (chacun sous les seuils individuels
   de `HighErrorRate`/`HighLatency`) peut quand même cumuler un budget
   d'erreur significatif sur la fenêtre — regarder le dashboard Golden
   Signals sur `1h`/`6h` pour repérer des pics passés inaperçus
   individuellement.

## Actions de remédiation (par ordre de priorité)

1. Traiter la cause racine via le runbook de l'alerte SPÉCIFIQUE
   concernée (`high-error-rate.md`, `high-latency.md`, `backend-down.md`)
   — il n'y a pas d'action de remédiation propre à `SLOViolation`
   elle-même, c'est un indicateur agrégé.
2. Une fois la cause corrigée, **ne pas s'attendre à une résolution
   instantanée** (voir critère ci-dessous).

## Critère de résolution

⚠️ **Différent des 4 autres alertes** : comme le calcul porte sur une
FENÊTRE GLISSANTE (1h sur ce cluster, 30j en "vrai" SLO — voir
`docs/slo.md`), la période d'incident reste comptabilisée dans le budget
consommé jusqu'à ce qu'elle "sorte" de la fenêtre glissante, MÊME APRÈS
que la cause a été corrigée. Concrètement : une panne de 10 minutes reste
visible dans le calcul de budget pendant encore ~50 minutes après sa
résolution (fenêtre de 1h) avant que `SLOViolation` ne repasse
`inactive` d'elle-même. Ne pas chercher une action manuelle pour "forcer"
la résolution — il n'y en a pas, et il ne devrait pas y en avoir (le but
du budget est justement de garder une mémoire de l'impact récent, pas de
l'effacer au premier correctif).
