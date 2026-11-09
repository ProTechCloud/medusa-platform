module "api" {
  source = "../../../modules/gcp/api-vm"

  project_id  = var.project_id
  name        = local.name
  region      = var.region
  zone        = var.zone
  environment = module.shared.environment
  app_port    = var.app_port
  labels      = merge(local.labels, { component = "api" })

  service_account_email      = local.setup.instance_service_account
  tunnel_token_secret_id     = module.tunnel_token.secret_id
  posthog_token_secret_id    = module.posthog_project_token.secret_id
  otel_traces_sampler_arg    = "0.1" # A tenth of the traces in prd, where traffic is real.
  artifact_registry_name     = module.registry.name
  artifact_registry_location = module.registry.location
}

# ---------- the API on Cloud Run, behind a Google load balancer ----------
# Beside the instance above until the hostname moves.
module "api_service" {
  source = "../../../modules/gcp/cloud-run-service"

  project_id            = var.project_id
  name                  = "${local.name}-api"
  region                = var.region
  service_account_email = local.setup.api_service_account
  image                 = "gcr.io/google-samples/hello-app@sha256:649188051906c9df7f87fb2ef04a21acbdb009c0877fa67b3132b83230411f6e" # hello-app:1.0
  env = {
    APP_ENV                 = module.shared.environment
    POSTHOG_HOST            = "https://us.i.posthog.com"
    LOG_POSTHOG_LEVEL       = "warn"
    LOG_STDOUT              = "true"
    LOG_LEVEL               = "info"
    OTEL_TRACES_SAMPLER_ARG = "0.1"
    NODE_ENV                = "production"
  }
  secret_env = var.api_reads_posthog_project_token ? {
    POSTHOG_PROJECT_TOKEN = { secret = module.posthog_project_token.secret_id }
  } : {}
  deletion_protection = module.shared.environment == "prd"
  labels              = merge(local.labels, { component = "api" })

  # Cloud Run checks a referenced secret when it creates the revision.
  depends_on = [google_secret_manager_secret_iam_member.api_reads_posthog_token]
}
