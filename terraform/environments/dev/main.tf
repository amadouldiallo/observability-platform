# =============================================================================
# Stockage objet pour Loki et Tempo — sur le cluster GKE EXISTANT du Projet 2
# =============================================================================
#
# ❓ Pourquoi il n'y a pas de module "gke" ici
# Contrairement aux Projets 1 et 2, ce projet ne crée PAS de cluster : le
# guide est explicite, il "transforme la plateforme des Projets 1 et 2" —
# créer un 3ᵉ cluster juste pour de l'observabilité dupliquerait un coût
# (control plane régional + nodes) sans raison technique, et contredirait
# la logique même du projet. Prometheus Operator, Loki, Tempo et tout le
# reste (Helm/kubectl, pas Terraform — voir k8s/) sont déployés sur le
# cluster `gitops-platform` déjà provisionné.
#
# Le pool Workload Identity utilisé ci-dessous (${var.project_id}.svc.id.goog)
# suppose donc que ce cluster existe déjà avec Workload Identity activé —
# vrai pour gitops-platform (Projet 2), vérifiable via :
#   gcloud container clusters describe gitops-platform --region europe-west1 \
#     --format="value(workloadIdentityConfig.workloadPool)"
module "storage" {
  source     = "../../modules/storage"
  project_id = var.project_id
  region     = var.region
  labels     = local.common_labels

  buckets = {
    loki = {
      name_suffix         = "loki-chunks"
      account_id          = "loki-storage"
      display_name        = "Loki — écriture chunks GCS"
      k8s_namespace       = "loki"
      k8s_service_account = "loki"
      retention_days      = var.loki_retention_days
    }
    tempo = {
      name_suffix         = "tempo-traces"
      account_id          = "tempo-storage"
      display_name        = "Tempo — écriture traces GCS"
      k8s_namespace       = "tracing"
      k8s_service_account = "tempo"
      retention_days      = var.tempo_retention_days
    }
  }

  depends_on = [google_project_service.required]
}
