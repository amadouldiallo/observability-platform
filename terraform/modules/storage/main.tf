# =============================================================================
# Stockage objet pour Loki (logs) et Tempo (traces) — Workload Identity
# =============================================================================
#
# 🎯 Le concept
# Loki et Tempo, par défaut, écrivent leurs données sur le disque du pod
# (PVC ou pire, `emptyDir`). Ici, ils écrivent directement dans deux buckets
# GCS dédiés, via un compte de service Google lié à un ServiceAccount
# Kubernetes précis — Workload Identity, sans clé JSON, même mécanisme que
# `opencost` au Projet 2 (voir modules/gke/main.tf du Projet 2 pour le détail
# pédagogique complet ; réécrit indépendamment ici, ce module ne référence
# aucun code des Projets 1/2).
#
# 🧠 Analogie
# Un PVC est un tiroir de bureau : pratique, mais s'il part avec le meuble
# (remplacement de node), tout son contenu part avec lui — vécu très
# concrètement avec Vault en mode dev au Projet 2 (Étape 7 : perte de
# configuration au remplacement du node pool). Un bucket GCS est un
# entrepôt externe : le bureau (le pod, le node) peut changer, l'entrepôt
# reste.
#
# ❓ Pourquoi c'est important ici précisément
# Ce cluster (`gitops-platform`, Projet 2) a déjà connu un remplacement de
# node pool en cours de lab (changement de `machine_type`). Loki et Tempo
# tournant en continu sur ce même cluster, la question n'est pas "si" un
# futur remplacement de node aura lieu, mais "quand" — stocker sur GCS dès
# le départ évite de revivre la perte de données du Projet 2.
#
# ⚠️ Piège à anticiper (documenté ici, pas encore rencontré) : le nom du
# ServiceAccount Kubernetes attendu par `k8s_service_account` DOIT
# correspondre exactement à celui créé par le chart Helm (Loki, Tempo) —
# à vérifier via `kubectl get sa -n <namespace>` AVANT d'annoter, plutôt que
# de supposer le nom par défaut du chart.

resource "google_storage_bucket" "buckets" {
  for_each = var.buckets

  project                     = var.project_id
  name                        = "${var.project_id}-${each.value.name_suffix}"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true

  # force_destroy = true : cohérent avec deletion_protection = false sur le
  # cluster GKE du Projet 2 — un lab d'apprentissage qu'on détruit/recrée
  # librement, pas une prod où l'on voudrait un garde-fou supplémentaire.
  force_destroy = true

  # FinOps : ces buckets accumulent en continu (logs, traces) sur un cluster
  # qui tourne 24/7 — sans purge automatique, leur coût croît indéfiniment
  # pour des données de lab dont la valeur diagnostique tombe vite après
  # quelques jours.
  lifecycle_rule {
    condition {
      age = each.value.retention_days
    }
    action {
      type = "Delete"
    }
  }

  labels = var.labels
}

resource "google_service_account" "workload_identity" {
  for_each = var.buckets

  project      = var.project_id
  account_id   = each.value.account_id
  display_name = each.value.display_name
}

# Accès scopé AU BUCKET précis (pas au projet entier) : moindre privilège —
# le compte de service de Loki n'a aucune raison de pouvoir toucher le
# bucket de Tempo, et inversement.
resource "google_storage_bucket_iam_member" "object_admin" {
  for_each = var.buckets

  bucket = google_storage_bucket.buckets[each.key].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.workload_identity[each.key].email}"
}

# ⚠️ Piège rencontré pour de vrai en démarrant Tempo (pas Loki, qui se
# contente d'`objectAdmin`) : `roles/storage.objectAdmin` couvre les
# opérations sur les OBJETS (lire/écrire/lister des fichiers), mais PAS
# `storage.buckets.get` — Tempo appelle cette permission AU DÉMARRAGE pour
# vérifier les attributs du bucket, et échouait en CrashLoopBackOff avec
# une erreur 403 explicite ("does not have storage.buckets.get access").
# `roles/storage.legacyBucketReader` ajoute précisément cette permission
# manquante, toujours scopée au bucket — pas la voie de facilité
# `roles/storage.admin` (qui ajouterait aussi le droit de supprimer le
# bucket lui-même, inutile ici). N'est demandé QUE par les buckets qui en
# ont réellement besoin (`extra_roles`), pas appliqué par défaut aux deux.
locals {
  extra_roles_flat = flatten([
    for key, b in var.buckets : [
      for role in b.extra_roles : { pair_key = "${key}/${role}", bucket_key = key, role = role }
    ]
  ])
}

resource "google_storage_bucket_iam_member" "extra_roles" {
  for_each = { for pair in local.extra_roles_flat : pair.pair_key => pair }

  bucket = google_storage_bucket.buckets[each.value.bucket_key].name
  role   = each.value.role
  member = "serviceAccount:${google_service_account.workload_identity[each.value.bucket_key].email}"
}

resource "google_service_account_iam_member" "workload_identity_binding" {
  for_each = var.buckets

  service_account_id = google_service_account.workload_identity[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value.k8s_namespace}/${each.value.k8s_service_account}]"
}
