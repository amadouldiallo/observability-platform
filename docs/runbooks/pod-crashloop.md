# Runbook — TaskTrackerPodCrashLooping

**Alerte** : `TaskTrackerPodCrashLooping` — un pod du namespace
`task-tracker` en `CrashLoopBackOff` depuis plus de 5 minutes.

## Symptômes observés

- Alertmanager / Prometheus : `TaskTrackerPodCrashLooping` en `firing`.
- `kubectl get pods -n task-tracker` : `STATUS` = `CrashLoopBackOff`,
  `RESTARTS` qui augmente.
- Selon le pod concerné : app indisponible (backend/frontend) ou données
  inaccessibles (db).

## Diagnostic immédiat

```bash
kubectl get pods -n task-tracker

# Le pod qui a planté redémarre AVANT que tu n'aies pu voir pourquoi —
# --previous récupère les logs du conteneur MORT, pas du nouveau qui
# vient de redémarrer (piège classique : lire les logs "actuels" d'un
# pod en CrashLoopBackOff ne montre souvent qu'un démarrage en cours,
# pas la cause du crash précédent).
kubectl logs <pod> -n task-tracker --previous

# Events récents : OOMKilled ? Probe échouée ? Image introuvable ?
kubectl describe pod <pod> -n task-tracker | tail -30
```

```promql
# Confirmation côté métriques (kube-state-metrics)
kube_pod_container_status_waiting_reason{namespace="task-tracker",reason="CrashLoopBackOff"}
```

## Actions de remédiation (par ordre de priorité)

1. **`--previous` d'abord, toujours** — la cause précise est presque
   toujours dans ces logs (exception Python non gérée, échec de connexion
   DB au démarrage, `PGPASSWORD` manquant...).
2. **`OOMKilled` ?** (`kubectl describe pod`, chercher `Reason: OOMKilled`
   dans les événements) — le conteneur a dépassé `resources.limits.memory`
   (chart Helm, `charts/app/values.yaml`) ; soit une vraie fuite mémoire,
   soit une limite mal calibrée.
3. **Secret manquant ou mal synchronisé** — si c'est le backend et que le
   crash suit un pattern de connexion DB échouée, vérifier
   `kubectl get externalsecret -n task-tracker` (Vault/ESO, Projet 2
   Étape 7) : un Secret vide ou périmé fait planter le pool de connexions
   dès `db.pool.open(wait=True, timeout=30)` au démarrage.
4. **Déploiement récent d'une image cassée** — `kubectl rollout undo`,
   ou repousser une image corrigée.

## Critère de résolution

Le pod reste `1/1 Running` sans nouveau redémarrage pendant plusieurs
minutes ; l'alerte repasse `inactive` d'elle-même une fois `for: 5m`
sans condition `CrashLoopBackOff` détectée.
