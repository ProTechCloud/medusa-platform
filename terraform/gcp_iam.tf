# ---------- identity the instance runs as ----------
# Reads exactly one secret and pulls from exactly one registry. Nothing else.

resource "google_service_account" "instance" {
  project      = var.gcp_project_id
  account_id   = "${local.name_prefix}-vm"
  display_name = "${var.service} ${var.environment} instance"
}

resource "google_secret_manager_secret_iam_member" "instance_reads_token" {
  project   = var.gcp_project_id
  secret_id = google_secret_manager_secret.tunnel_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.instance.email}"
}

resource "google_artifact_registry_repository_iam_member" "instance_pulls" {
  project    = var.gcp_project_id
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.instance.email}"
}

resource "google_project_iam_member" "instance_logging" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.instance.email}"
}

# ---------- identity GitHub Actions deploys as ----------
# Scoped to: push images, reach the box over IAP, restart the service.

resource "google_service_account" "deployer" {
  project      = var.gcp_project_id
  account_id   = "${local.name_prefix}-deployer"
  display_name = "${var.service} ${var.environment} CI deployer"
}

resource "google_artifact_registry_repository_iam_member" "deployer_pushes" {
  project    = var.gcp_project_id
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_project_iam_member" "deployer_roles" {
  for_each = toset([
    "roles/compute.instanceAdmin.v1",   # restart / inspect the instance
    "roles/iap.tunnelResourceAccessor", # reach port 22 without a public rule
    # osAdminLogin, not osLogin: the rollout runs `sudo /etc/medusa/deploy.sh`,
    # and plain osLogin lands you on the box without sudo.
    "roles/compute.osAdminLogin",
  ])

  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# The deployer must be able to act as the instance SA to use `gcloud compute ssh`.
resource "google_service_account_iam_member" "deployer_impersonates_instance" {
  service_account_id = google_service_account.instance.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}

