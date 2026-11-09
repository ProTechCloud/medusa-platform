output "state_bucket" {
  description = "Bucket holding this environment's workload state. Passed to init with -backend-config."
  value       = module.state.name
}

output "state_key" {
  value = module.state.kms_key_id
}

output "secrets_key" {
  description = "Key encrypting this environment's secrets. Separate from the state key on purpose."
  value       = google_kms_crypto_key.secrets.id
}

output "plan_spoke" {
  value = module.plan_spoke.email
}

output "apply_spoke" {
  value = module.apply_spoke.email
}

output "tunnel_token_writer" {
  description = "Identity the deploy job uses to write the tunnel token. The workload root grants it access to that one secret."
  value       = module.tunnel_token_writer.email
}

output "posthog_token_writer" {
  description = "Identity the PostHog apply uses to write the project token, passed through from org/gcp/_setup: the workload root reads only this root's outputs."
  value       = local.org.posthog_token_writer
}

output "deploy_spoke" {
  description = "Identity medusa-app deploys as. Empty outside stg."
  value       = one(module.deploy_spoke[*].email)
}

output "instance_service_account" {
  description = "Identity the VM runs as. Created here so the apply spoke never needs serviceAccountAdmin."
  value       = google_service_account.instance.email
}

output "api_service_account" {
  description = "Identity the Cloud Run service runs as. Created here so the apply spoke never needs serviceAccountAdmin."
  value       = google_service_account.api.email
}

output "workload_identity_pool" {
  description = "Passed through from org/gcp/_setup: the workload root reads only this root's outputs."
  value       = local.org.workload_identity_pool
}

output "platform_repository" {
  description = "owner/name of this repository, for the trust rules on this environment's hubs."
  value       = local.org.platform_repository
}

output "backend_repository" {
  description = "owner/name of the application repository, for the deploy hub's trust rule."
  value       = local.org.backend_repository
}

output "tunnel_token_hub_name" {
  description = "Full resource name of this environment's tunnel-token hub."
  value       = local.org.tunnel_token_hub_names[var.environment]
}

output "backend_deploy_hub_name" {
  description = "Full resource name of the backend deploy hub. Empty outside stg."
  value       = var.environment == "stg" ? local.org.backend_deploy_hub_name : null
}
