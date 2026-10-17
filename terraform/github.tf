# The deploy workflow in medusa-backend reads exactly these. They are written
# here and nowhere else — no secret is ever typed into the GitHub UI by hand,
# and rotating one means re-applying this stack, not editing a web form.

data "github_repository" "backend" {
  full_name = "${var.github_owner}/${var.backend_repository}"
}


resource "github_actions_secret" "config" {
  for_each = {
    GCP_PROJECT_ID    = var.gcp_project_id
    GCP_REGION        = var.gcp_region
    GCP_ZONE          = var.gcp_zone
    GCP_VM_NAME       = google_compute_instance.api.name
    GCP_AR_REPOSITORY = google_artifact_registry_repository.images.repository_id

    # Keyless auth. Neither value is a secret on its own — they are stored as
    # secrets only to keep the project layout out of public workflow logs.
    GCP_WORKLOAD_IDENTITY_PROVIDER = google_iam_workload_identity_pool_provider.github.name
    GCP_SERVICE_ACCOUNT            = google_service_account.deployer.email
  }

  repository      = data.github_repository.backend.name
  secret_name     = each.key
  plaintext_value = each.value
}

# A deploy environment gate so STG rollouts are auditable and can require review later.
resource "github_repository_environment" "stg" {
  repository  = data.github_repository.backend.name
  environment = var.environment

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "stg_branch" {
  repository     = data.github_repository.backend.name
  environment    = github_repository_environment.stg.environment
  branch_pattern = "STG"
}
