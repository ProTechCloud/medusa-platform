output "public_url" {
  description = "Where the API answers once the tunnel is up."
  value       = "https://${local.hostname}"
}

output "tunnel_id" {
  description = "Cloudflare tunnel the instance registers with."
  value       = cloudflare_zero_trust_tunnel_cloudflared.api.id
}

output "instance_name" {
  description = "GCE instance running the app and the connector."
  value       = google_compute_instance.api.name
}

output "artifact_registry" {
  description = "Image repository CI pushes to."
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "deployer_service_account" {
  description = "Identity GitHub Actions authenticates as."
  value       = google_service_account.deployer.email
}

output "tunnel_token_secret" {
  description = "Secret Manager entry the instance reads at boot."
  value       = google_secret_manager_secret.tunnel_token.secret_id
}

output "github_secrets_written" {
  description = "Secrets this stack manages in the backend repository."
  value = concat(
    [github_actions_secret.gcp_sa_key.secret_name],
    [for s in github_actions_secret.config : s.secret_name],
  )
}
