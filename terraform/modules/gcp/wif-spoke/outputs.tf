output "email" {
  description = "Spoke service account email."
  value       = google_service_account.spoke.email
}

output "member" {
  description = "IAM member string for use in deny policies and resource-level bindings."
  value       = "serviceAccount:${google_service_account.spoke.email}"
}

output "principal" {
  description = "Principal identifier in the form IAM deny policies expect."
  value       = "principal://iam.googleapis.com/projects/-/serviceAccounts/${google_service_account.spoke.unique_id}"
}
