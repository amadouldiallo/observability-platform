variable "project_id" {
  # Pas de défaut : peut être le même projet GCP que les Projets 1/2 (celui
  # qui héberge déjà le cluster gitops-platform), ou un projet distinct —
  # jamais codé en dur ici.
  description = "ID du projet GCP cible — doit héberger le cluster GKE sur lequel Prometheus/Loki/Tempo seront déployés (kubectl, hors Terraform)"
  type        = string
}

variable "region" {
  description = "Région GCP des buckets de stockage — idéalement celle du cluster GKE existant"
  type        = string
  default     = "europe-west1"
}

variable "environment" {
  description = "Label FinOps 'environment'"
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,63}$", var.environment))
    error_message = "environment doit être en minuscules, [a-z0-9_-], 63 caractères max (contrainte de label GCP)."
  }
}

variable "cost_center" {
  description = "Label FinOps 'cost_center'"
  type        = string
  default     = "lab-perso"

  validation {
    condition     = can(regex("^[a-z0-9_-]{1,63}$", var.cost_center))
    error_message = "cost_center doit être en minuscules, [a-z0-9_-], 63 caractères max (contrainte de label GCP)."
  }
}

variable "extra_labels" {
  description = "Labels FinOps additionnels, fusionnés par-dessus le socle"
  type        = map(string)
  default     = {}
}

variable "loki_retention_days" {
  description = "Durée de rétention des chunks Loki dans GCS avant purge automatique (lifecycle rule)"
  type        = number
  default     = 14
}

variable "tempo_retention_days" {
  # Plus court que Loki : la valeur diagnostique d'une trace individuelle
  # (contrairement à un log ou une métrique agrégée) tombe très vite —
  # utile pour déboguer un incident récent, rarement pour une analyse a
  # posteriori sur plusieurs semaines.
  description = "Durée de rétention des traces Tempo dans GCS avant purge automatique (lifecycle rule)"
  type        = number
  default     = 7
}
