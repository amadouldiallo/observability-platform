# Runbook — BackendDown

**Alerte** : `BackendDown` — plus aucune cible `task-tracker-backend`
dans Prometheus depuis plus de 2 minutes (`absent(up{job="task-tracker-backend"})`).

Ce runbook est écrit à partir d'un incident RÉELLEMENT provoqué et vécu
(voir [docs/incident-drill.md](../incident-drill.md), Étape 8) — pas
d'une supposition.

## Symptômes observés

- Alertmanager / Prometheus : `BackendDown` en `firing`.
- `https://.../api/tasks` renvoie `502`/`503` (nginx-ingress, aucun
  endpoint derrière le Service).
- Dashboard Golden Signals : panel "Traffic" tombe à zéro.
- **Piège de diagnostic** : `up{job="task-tracker-backend"}` ne renvoie
  PAS `0` — il ne renvoie **rien du tout** (vecteur vide). Kubernetes
  retire l'Endpoint du Service dès que le dernier pod disparaît, et
  Prometheus retire la cible elle-même de sa liste active. Si tu
  cherches un `up == 0` pour confirmer, tu ne trouveras rien — ce n'est
  pas que l'alerte ment, c'est que la bonne requête est
  `absent(up{job="task-tracker-backend"})`, pas une comparaison à 0.

## Diagnostic immédiat

```bash
# Combien de pods existent VRAIMENT (pas juste "prêts")
kubectl get pods -n task-tracker -l app.kubernetes.io/name=backend

# L'état déclaré du Deployment — 0 réplica est-il VOULU (Git) ou une dérive ?
kubectl get deployment task-tracker-backend -n task-tracker -o jsonpath='{.spec.replicas}{"\n"}'

# Argo CD : l'automatisation (selfHeal) est-elle active ?
kubectl get application task-tracker -n argocd -o jsonpath='{.spec.syncPolicy}{"\n"}'

# État de synchro Argo CD — un "OutOfSync" confirme une dérive
kubectl get application task-tracker -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
```

## Actions de remédiation (par ordre de priorité)

1. **`syncPolicy.automated` est-elle désactivée ?** Si oui (ex. laissée
   éteinte après une opération de maintenance, voir l'incident réel
   documenté dans `docs/incident-drill.md`), c'est très probablement la
   cause : rien ne corrige plus les dérives automatiquement.
   ```bash
   kubectl patch application task-tracker -n argocd --type merge \
     -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
   ```
   **Vérifié en conditions réelles** : avec `selfHeal: true` actif, un
   `replicas=0` accidentel est corrigé tout seul en **~3 secondes** — pas
   besoin d'aller plus loin dans ce cas.
2. **Si `selfHeal` est actif mais que ça ne suffit pas** : le Deployment
   est peut-être correctement à `replicas=1` mais le pod ne DÉMARRE pas
   (`ImagePullBackOff`, quota de ressources épuisé — voir les leçons CPU
   des Étapes 1/2 de ce projet). `kubectl describe deployment
   task-tracker-backend -n task-tracker` pour les événements de
   scheduling.
3. **Si un humain a VOLONTAIREMENT scalé à 0** (ex. maintenance en
   cours) : ce n'est pas un incident, c'est un état attendu — vérifier
   avec l'équipe avant d'intervenir, plutôt que de rétablir un service en
   cours de maintenance planifiée.
4. Une fois la cause corrigée, remonter manuellement si nécessaire :
   `kubectl scale deployment task-tracker-backend --replicas=1 -n task-tracker`
   (Argo CD, une fois `selfHeal` réactivé, le referait de toute façon).

## Critère de résolution

Pod `1/1 Running`, `up{job="task-tracker-backend"}` réapparaît avec la
valeur `1`, `https://.../api/tasks` renvoie `200`. `BackendDown` repasse
`inactive` automatiquement dès que la cible réapparaît — **vérifié en
conditions réelles** : ~45 secondes après le retour du pod.
