output "bucket_names" {
  description = "Map clé -> nom du bucket GCS créé"
  value       = { for k, b in google_storage_bucket.buckets : k => b.name }
}

output "bucket_urls" {
  description = "Map clé -> URL gs:// du bucket"
  value       = { for k, b in google_storage_bucket.buckets : k => b.url }
}

output "service_account_emails" {
  description = "Map clé -> email du compte de service Workload Identity créé"
  value       = { for k, sa in google_service_account.workload_identity : k => sa.email }
}
