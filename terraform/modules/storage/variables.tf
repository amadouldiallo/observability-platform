variable "project_id" {
  description = "ID du projet GCP cible (le même que celui hébergeant le cluster gitops-platform du Projet 2, ou un projet distinct)"
  type        = string
}

variable "region" {
  description = "Région GCP des buckets (idéalement la même que le cluster, pour éviter la latence/coût de sortie inter-région)"
  type        = string
}

variable "buckets" {
  description = "Buckets GCS à créer, un par consommateur (Loki, Tempo), avec leur ServiceAccount Kubernetes cible pour le binding Workload Identity"
  type = map(object({
    name_suffix         = string
    account_id          = string
    display_name        = string
    k8s_namespace       = string
    k8s_service_account = string
    retention_days      = number
    # Rôles IAM SUPPLÉMENTAIRES, au-delà de storage.objectAdmin (déjà
    # accordé à tous) — vide par défaut, rempli uniquement pour un
    # consommateur qui en a un besoin démontré (voir main.tf : Tempo a
    # besoin de storage.legacyBucketReader, pas Loki).
    extra_roles = optional(list(string), [])
  }))
}

variable "labels" {
  description = "Labels FinOps appliqués aux buckets"
  type        = map(string)
  default     = {}
}
