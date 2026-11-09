# The identity the Cloud Run service runs as. Created here for the same reason
# as the instance's: the apply identity never needs serviceAccountAdmin.
resource "google_service_account" "api" {
  account_id   = "medusa-${var.environment}-api"
  project      = var.project_id
  display_name = "medusa ${var.environment} api"
  description  = "Runs the API on Cloud Run."
}

# Deploying a service that runs as an identity is a permission on the identity,
# not on the service.
resource "google_service_account_iam_member" "apply_attaches_api" {
  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountUser"
  member             = module.apply_spoke.member
}

# A new revision runs as this identity, so the deploy needs this too, on this
# one account and not project-wide.
resource "google_service_account_iam_member" "deploy_acts_as_api" {
  count = var.environment == "stg" ? 1 : 0

  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountUser"
  member             = module.deploy_spoke[0].member
}
