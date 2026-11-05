locals {
  org = data.terraform_remote_state.org.outputs

  plan_hub  = "serviceAccount:${local.org.plan_hubs[var.environment]}"
  apply_hub = "serviceAccount:${local.org.apply_hubs[var.environment]}"
}

locals {
  # Only stg has one: the application deploys to stg and nowhere else.
  backend_deploy_hub = "serviceAccount:${local.org.backend_deploy_hub}"
  tunnel_token_hub   = "serviceAccount:${local.org.tunnel_token_hubs[var.environment]}"
}
