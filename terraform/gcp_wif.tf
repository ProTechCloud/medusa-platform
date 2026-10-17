# Workload Identity Federation — keyless auth for GitHub Actions.
#
# The organization enforces constraints/iam.disableServiceAccountKeyCreation,
# so there is no long-lived JSON key to mint, store or rotate. Instead GitHub
# presents its OIDC token and GCP exchanges it for a short-lived access token.
# Nothing secret is ever written to GitHub: the two values stored there are an
# identifier and an email, useless without a matching OIDC assertion.

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.gcp_project_id
  workload_identity_pool_id = "${local.name_prefix}-gh"
  display_name              = "GitHub Actions"
  description               = "Federated identity for ${var.github_owner}/${var.backend_repository}"

  depends_on = [google_project_service.enabled]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.gcp_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.actor"      = "assertion.actor"
  }

  # Without this condition ANY GitHub repository on the internet could exchange
  # a token here. It is the single most important line in this file.
  # The pool admits both repositories; which service account each one may
  # actually impersonate is pinned separately, per repository, in the bindings.
  attribute_condition = "assertion.repository in ['${var.github_owner}/${var.backend_repository}', '${var.github_owner}/${var.platform_repository}']"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Only workflows running in the backend repository may impersonate the deployer.
resource "google_service_account_iam_member" "github_impersonates_deployer" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.backend_repository}"
}

# ---------- Terraform's own CI identity ----------
# Scoped to what this stack manages. Deliberately not owner or editor: it
# cannot reach billing, org policy, or anything outside these services.

resource "google_service_account" "terraform_ci" {
  project      = var.gcp_project_id
  account_id   = "${var.service}-tf-ci"
  display_name = "Terraform CI (${var.platform_repository})"
}

resource "google_project_iam_member" "terraform_ci_roles" {
  for_each = toset([
    "roles/compute.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/secretmanager.admin",
    "roles/artifactregistry.admin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/iam.serviceAccountUser",
    "roles/storage.admin",
  ])

  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform_ci.email}"
}

# Only workflows in the platform repository may impersonate the Terraform SA.
resource "google_service_account_iam_member" "github_impersonates_terraform_ci" {
  service_account_id = google_service_account.terraform_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_owner}/${var.platform_repository}"
}
