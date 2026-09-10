# Projet 3 — Observability & SRE Platform
## Guide d'apprentissage pédagogique

**Objectif du projet :** transformer la plateforme Kubernetes des Projets 1 et 2 en environnement réellement exploitable selon une approche SRE — visibilité complète (métriques, logs, traces), objectifs de fiabilité chiffrés, et réponse à incident outillée.

---

## Étape 1 — Métriques (Prometheus)

**🎯 Le concept**
Collecter en continu des indicateurs numériques (CPU, latence, taux d'erreur) sur chaque composant.

**🧠 Analogie**
Prometheus est le tableau de bord d'une voiture : il ne dit pas "c'est cassé", il donne en continu la vitesse, la température moteur, le niveau d'essence — à toi de repérer les patterns anormaux. Le Prometheus Operator + ServiceMonitor branche automatiquement un nouveau capteur (une nouvelle appli) dès qu'elle apparaît sur le circuit (Kubernetes), sans câblage manuel.

**❓ Pourquoi**
Sans métriques, on découvre les problèmes via les plaintes utilisateurs, pas avant. C'est la différence entre visibilité proactive et réactive.

**🛠️ Prompt Claude Code**
```
Déploie le Prometheus Operator sur le cluster (kube-prometheus-stack), puis
crée un ServiceMonitor qui scrape automatiquement les métriques /metrics
du backend (requêtes, latence, erreurs) exposées via une librairie
Prometheus client.
```

---

## Étape 2 — Logs (Loki)

**🎯 Le concept**
Centraliser les logs de tous les pods à un seul endroit interrogeable, plutôt que `kubectl logs` pod par pod.

**🧠 Analogie**
Loki est une bibliothèque qui indexe seulement les étagères (labels : namespace, pod, app) et pas le contenu de chaque livre — contrairement à Elasticsearch qui indexe tout le texte. Beaucoup moins cher à faire tourner, au prix d'une recherche plein-texte moins puissante : un compromis assumé, pas un défaut.

**❓ Pourquoi**
Sans centralisation, débugger un incident qui traverse 3 pods = ouvrir 3 terminaux et croiser les timestamps à la main.

**🛠️ Prompt Claude Code**
```
Installe Loki + Promtail (ou Grafana Alloy) pour centraliser les logs
stdout/stderr de tous les pods du namespace task-tracker, avec Grafana
comme interface de requête.
```

---

## Étape 3 — Distributed Tracing (OpenTelemetry + Tempo)

**🎯 Le concept**
Suivre une seule requête utilisateur à travers tous les services qu'elle traverse, avec le temps passé dans chacun.

**🧠 Analogie**
Une trace distribuée, c'est un colis avec un numéro de suivi unique qui passe par plusieurs entrepôts (frontend → backend → base de données) — au lieu d'appeler chaque entrepôt séparément, un seul numéro (`trace_id`) montre le trajet complet et le temps passé à chaque étape.

**❓ Pourquoi**
Les métriques disent "le p99 a augmenté", les logs disent "il y a eu une erreur ici" — seule une trace dit précisément quel appel, dans quel service, a pris 800ms sur les 900ms totaux d'une requête lente.

**🛠️ Prompt Claude Code**
```
Instrumente le backend avec OpenTelemetry (auto-instrumentation
Python/FastAPI), exporte les traces vers Tempo, et connecte Tempo à
Grafana pour visualiser le parcours complet d'une requête
frontend → backend → PostgreSQL.
```

---

## Étape 4 — Golden Signals

**🎯 Le concept**
4 métriques qui, ensemble, donnent une vue suffisante de la santé de n'importe quel service : Latency, Traffic, Errors, Saturation.

**🧠 Analogie**
Ce sont les 4 constantes vitales d'un patient aux urgences (pouls, tension, température, saturation en oxygène) — un médecin regarde ces 4-là en premier pour juger de la gravité, avant de creuser plus loin.

**❓ Pourquoi**
Sans ce cadre, on peut créer 40 dashboards dispersés sans jamais répondre vite à "est-ce que le service va bien, là, maintenant ?". C'est le standard SRE popularisé par le Google SRE Book.

**🛠️ Prompt Claude Code**
```
Crée un dashboard Grafana "Golden Signals" pour le backend, avec 4
panels : Latency (p50/p95/p99), Traffic (requêtes/seconde), Errors
(taux d'erreur 5xx), Saturation (CPU/mémoire vs limits).
```

---

## Étape 5 — SLI

**🎯 Le concept**
Un Service Level Indicator est une métrique précise et mesurable de la qualité perçue par l'utilisateur (ex : % de requêtes réussies).

**🧠 Analogie**
C'est le thermomètre, pas la température idéale — le SLI est juste "ce qu'on mesure", une formule précise, sans jugement de valeur sur ce qui est "bien" ou "mal" (ça, c'est le SLO, à l'étape suivante).

**❓ Pourquoi**
Sans définition précise, "le service va bien" est une opinion. Avec un SLI, c'est un chiffre vérifiable en continu.

**🛠️ Prompt Claude Code**
```
Définis 3 SLI Prometheus pour le backend : disponibilité (requêtes
2xx/3xx / total), taux d'erreur (5xx / total), latence (% de requêtes
sous 300ms), sous forme de requêtes PromQL prêtes à l'emploi.
```

---

## Étape 6 — SLO

**🎯 Le concept**
Un objectif chiffré sur un SLI, sur une période donnée (ex : disponibilité ≥ 99,9 % sur 30 jours), qui définit ce qu'est un service "acceptable".

**🧠 Analogie**
Si le SLI est le thermomètre, le SLO est la plage de température acceptable définie par le médecin — en dessous ou au-dessus, on agit. Ce n'est pas "100 % parfait à chaque instant" (impossible et inutile), c'est un objectif réaliste avec une marge d'erreur assumée : l'**error budget**.

**❓ Pourquoi**
Sans SLO, chaque incident déclenche une réaction disproportionnée ou, à l'inverse, aucune réaction. Le SLO donne une règle objective pour savoir quand escalader.

**🛠️ Prompt Claude Code**
```
Définis les SLO suivants pour le backend et documente-les dans
docs/slo.md : disponibilité 99,9% sur 30 jours, latence p95 < 300ms,
taux d'erreur < 0,1% — avec le calcul de l'error budget correspondant
en minutes d'indisponibilité tolérées par mois.
```

---

## Étape 7 — Alerting

**🎯 Le concept**
Déclencher une notification automatique uniquement quand un SLO est en train d'être violé (ou va l'être) — pas à chaque anomalie mineure.

**🧠 Analogie**
Une bonne alerte est un détecteur de fumée bien calibré : il sonne pour un vrai feu, pas à chaque fois que tu grilles du pain. Une alerte mal calibrée qui sonne trop souvent pour rien est pire que pas d'alerte du tout — elle finit débranchée.

**❓ Pourquoi**
Trop d'alertes = fatigue d'alerte, l'équipe ignore les notifications à force de faux positifs. Une alerte doit être actionnable : si personne ne sait quoi faire en la recevant, elle ne devrait pas exister.

**🛠️ Prompt Claude Code**
```
Crée des règles d'alerte Prometheus (Alertmanager) : HighErrorRate
(>1% sur 5min), HighLatency (p95 > 500ms sur 5min), PodCrashLooping,
SLOViolation (error budget consommé à plus de 80%). Chaque alerte doit
inclure un lien vers le runbook correspondant.
```

---

## Étape 8 — Simulation d'incident

**🎯 Le concept**
Provoquer volontairement une panne pour vérifier que toute la chaîne d'observabilité (détection → alerte → dashboard → runbook) fonctionne réellement, avant qu'un vrai incident ne le révèle.

**🧠 Analogie**
C'est l'exercice incendie d'un immeuble — on ne veut pas découvrir que l'alarme ne sonne pas le jour d'un vrai feu. Provoquer une panne contrôlée est la seule façon de vérifier que la chaîne complète fonctionne, pas juste chaque brique isolément.

**❓ Pourquoi**
Prometheus, Alertmanager et Grafana peuvent chacun fonctionner en test isolément — seule une vraie panne déclenchée vérifie la chaîne bout-en-bout.

**🛠️ Prompt Claude Code**
```
Documente et exécute un scénario d'incident contrôlé :
kubectl scale deployment backend --replicas=0, puis observe et note
les délais réels entre chaque étape : détection Prometheus,
déclenchement Alertmanager, apparition dans Grafana, jusqu'au retour
à replicas=3.
```

---

## Étape 9 — Runbooks

**🎯 Le concept**
Un document court et actionnable qui dit précisément quoi faire quand une alerte spécifique se déclenche — écrit avant l'incident, pas pendant.

**🧠 Analogie**
C'est la checklist d'un pilote en cas de panne moteur — personne n'improvise une procédure de sécurité en plein vol. Elle est écrite, testée et suivie à la lettre, précisément parce que le moment de la panne est le pire moment pour réfléchir calmement.

**❓ Pourquoi**
Sous stress (astreinte à 3h du matin), la mémoire et le jugement sont dégradés. Un bon runbook transforme "je dois réfléchir à quoi faire" en "je suis les 5 étapes écrites".

**🛠️ Prompt Claude Code**
```
Crée 5 runbooks dans docs/runbooks/ (high-error-rate.md,
high-latency.md, pod-crashloop.md, node-not-ready.md, slo-breach.md),
chacun avec : symptômes observés, requêtes PromQL/kubectl de
diagnostic immédiat, actions de remédiation par ordre de priorité, et
critère de résolution.
```

---

## 💡 Lien avec le Projet 2 (FinOps)

Le même Prometheus déployé ici peut servir de socle à OpenCost (déjà en place dans le Projet 2) : les métriques `container_cpu_allocation` utilisées pour le coût par namespace et celles utilisées ici pour les Golden Signals proviennent de la même source. Un dashboard Grafana peut donc, à terme, afficher fiabilité (SLO) et coût côte à côte — deux vues d'une même plateforme, pas deux stacks séparées.

---

## Prochaine étape suggérée

Le **Projet 4 (DevSecOps & Supply Chain Security)** s'appuie sur cette même plateforme : SAST, scan de vulnérabilités (Trivy), SBOM (Syft/SPDX), signature d'images (Cosign), politiques d'admission (Kyverno) et détection runtime (Falco).
