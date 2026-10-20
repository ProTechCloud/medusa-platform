# The identity the box runs as. It reads one secret and pulls from one
# registry; it cannot change anything, including itself.
resource "google_service_account" "instance" {
  project      = var.project_id
  account_id   = "${var.name}-vm"
  display_name = "medusa ${var.environment} instance"
}

resource "google_secret_manager_secret_iam_member" "reads_tunnel_token" {
  project   = var.project_id
  secret_id = var.tunnel_token_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.instance.email}"
}

resource "google_artifact_registry_repository_iam_member" "pulls_images" {
  project    = var.project_id
  location   = var.artifact_registry_location
  repository = var.artifact_registry_name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.instance.email}"
}

resource "google_project_iam_member" "writes_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.instance.email}"
}
