# The container only, like the tunnel token. The PostHog apply reads the
# project token from its own state and writes it here as a new version, so the
# value never reaches this state file.
module "posthog_project_token" {
  source = "../../../modules/gcp/secret"

  project_id  = var.project_id
  environment = module.shared.environment
  domain      = "posthog"
  name        = "posthog-project-token"
  location    = var.region
  kms_key     = local.setup.secrets_key
  labels      = merge(local.labels, { component = "secret" })
}

# Add a version and nothing else: the PostHog apply cannot read one back.
resource "google_secret_manager_secret_iam_member" "posthog_writer_adds_versions" {
  project   = var.project_id
  secret_id = module.posthog_project_token.secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = local.setup.posthog_token_writer
}

resource "google_secret_manager_secret_iam_member" "api_reads_posthog_token" {
  project   = var.project_id
  secret_id = module.posthog_project_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.setup.api_service_account}"
}
