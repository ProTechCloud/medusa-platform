module "api" {
  source = "../../../modules/gcp/api-vm"

  project_id  = var.project_id
  name        = local.name
  region      = var.region
  zone        = var.zone
  environment = var.environment
  app_port    = var.app_port
  labels      = merge(local.labels, { component = "api" })

  service_account_email      = local.setup.instance_service_account
  tunnel_token_secret_id     = module.tunnel_token.secret_id
  posthog_token_secret_id    = module.posthog_project_token.secret_id
  otel_traces_sampler_arg    = "1" # Every trace in stg.
  artifact_registry_name     = module.registry.name
  artifact_registry_location = module.registry.location
}
