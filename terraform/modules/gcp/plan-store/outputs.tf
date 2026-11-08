output "name" {
  description = "Bucket name, which the plan workflows upload to."
  value       = google_storage_bucket.plans.name
}
