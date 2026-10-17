resource "google_project_service" "enabled" {
  for_each = toset(local.gcp_services)

  project = var.gcp_project_id
  service = each.value

  # Leave APIs on if the stack is destroyed — other things may depend on them.
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "images" {
  project       = var.gcp_project_id
  location      = var.gcp_region
  repository_id = local.name_prefix
  format        = "DOCKER"
  description   = "Container images for ${var.service} (${var.environment})"
  labels        = local.common_labels

  # Keep the registry small: only the 10 most recent images survive.
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  depends_on = [google_project_service.enabled]
}

# ---------- the tunnel credential, at rest in Secret Manager ----------

resource "google_secret_manager_secret" "tunnel_token" {
  project   = var.gcp_project_id
  secret_id = "${local.name_prefix}-tunnel-token"
  labels    = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.enabled]
}

resource "google_secret_manager_secret_version" "tunnel_token" {
  secret      = google_secret_manager_secret.tunnel_token.id
  secret_data = data.cloudflare_zero_trust_tunnel_cloudflared_token.api.token
}
