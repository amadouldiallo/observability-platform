terraform {
  required_version = ">= 1.9"

  # Bloc volontairement VIDE — voir Projet 1 pour l'explication complète
  # (un bloc `backend` ne peut pas référencer de variable). Configuration
  # fournie via `terraform init -backend-config=backend.hcl` :
  #   1. cp backend.hcl.example backend.hcl   (gitignored)
  #   2. éditer backend.hcl avec ton propre bucket
  #   3. terraform init -backend-config=backend.hcl
  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}
