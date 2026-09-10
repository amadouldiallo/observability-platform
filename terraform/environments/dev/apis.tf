# =============================================================================
# APIs GCP requises — activées explicitement, pas supposées pré-activées
# =============================================================================
#
# ❓ Pourquoi c'est important
# Même principe que les Projets 1 et 2 (voir leur apis.tf respectif) : ne
# jamais supposer qu'une API est déjà active parce qu'un AUTRE projet du
# même compte GCP l'a activée un jour. Liste volontairement courte ici —
# ce module ne crée ni cluster ni réseau (le cluster existe déjà, Projet 2),
# seulement du stockage et de l'IAM.
resource "google_project_service" "required" {
  for_each = toset([
    "storage.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
}
