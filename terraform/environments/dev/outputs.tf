output "bucket_names" {
  description = "Noms des buckets GCS créés (loki, tempo)"
  value       = module.storage.bucket_names
}

output "workload_identity_service_account_emails" {
  description = "Emails des comptes de service Workload Identity (à utiliser dans les values.yaml Helm de Loki/Tempo)"
  value       = module.storage.service_account_emails
}
