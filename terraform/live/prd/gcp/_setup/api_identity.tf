# The identity the Cloud Run service runs as. Created here, not in the workload
# root, so the apply identity never needs serviceAccountAdmin. That role cannot
# be narrowed: IAM conditions can only read resource.name for services that
# publish it, and iam.googleapis.com does not, so an unconditioned grant would
# let the apply identity edit every service account in the project, its own
# spokes included.
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
