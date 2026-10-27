# The identity the box runs as is created by the environment's _setup root and
# passed in, so the apply identity never needs permission to create a service
# account. What is granted here is only what the instance may reach: one
# secret, one registry, and its own logs and metrics.

resource "google_secret_manager_secret_iam_member" "reads_tunnel_token" {
  project   = var.project_id
  secret_id = var.tunnel_token_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.service_account_email}"
}

resource "google_artifact_registry_repository_iam_member" "pulls_images" {
  project    = var.project_id
  location   = var.artifact_registry_location
  repository = var.artifact_registry_name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${var.service_account_email}"
}

resource "google_project_iam_member" "writes_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${var.service_account_email}"
}

# The instance metadata asks Container-Optimized OS to run its monitoring
# agent, and the agent publishes as the instance's own identity. Without this
# binding the metadata changes nothing: memory and disk series never appear,
# and an alert on them sits there looking configured and never fires.
resource "google_project_iam_member" "writes_metrics" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${var.service_account_email}"
}
