# FinOps — voir le Projet 1 (locals.tf) pour l'explication complète des
# contraintes de label GCP. Réécrit indépendamment ici, avec un label
# `platform` distinct (`observability-platform`) : ce projet PARTAGE le
# projet GCP (et donc le compte de facturation) du Projet 2, sans partager
# son code — ce label est ce qui permettrait, plus tard, de distinguer sa
# propre dépense dans un budget filtré, exactement comme le Projet 2 le
# fait déjà pour se distinguer du Projet 1.
locals {
  common_labels = merge(
    {
      environment = var.environment
      cost_center = var.cost_center
      managed_by  = "terraform"
      platform    = "observability-platform"
    },
    var.extra_labels
  )
}
