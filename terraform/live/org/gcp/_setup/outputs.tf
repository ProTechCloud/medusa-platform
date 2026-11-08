# Every other root reads these through terraform_remote_state. Values are
# never copied between roots by hand: a stale copy of an identity name fails
# as a permission error at apply time, which is the hardest kind to diagnose.

output "management_project_id" {
  value = var.management_project_id
}

output "management_state_bucket" {
  description = "Bucket for org, _setup and Cloudflare state. Passed to init with -backend-config."
  value       = module.management_state.name
}

output "management_state_key" {
  value = module.management_state.kms_key_id
}

output "environment_projects" {
  description = "Project id per environment."
  value       = { for k, m in module.environment_project : k => m.project_id }
}

output "environment_project_numbers" {
  value = { for k, m in module.environment_project : k => m.number }
}

output "workload_identity_pool" {
  value = google_iam_workload_identity_pool.github.name
}

output "plan_provider" {
  description = "Full provider resource name the plan workflows pass to the auth action."
  value       = google_iam_workload_identity_pool_provider.plan.name
}

output "apply_provider" {
  value = google_iam_workload_identity_pool_provider.apply.name
}

output "audience" {
  description = "Audience the workflows must request. Pinning it stops a token minted for another Google resource from being replayed here."
  value       = local.audience
}

output "plan_hubs" {
  description = "Plan hub email per environment. The environment's plan spoke trusts exactly this."
  value       = { for k, m in module.plan_hub : k => m.email }
}

output "apply_hubs" {
  value = { for k, m in module.apply_hub : k => m.email }
}

output "tunnel_token_hubs" {
  description = "Tunnel-token hub per environment. Separate hubs: a shared one would let one environment's deploy write another's secret."
  value       = { for k, h in google_service_account.tunnel_token_hub : k => h.email }
}

output "tunnel_token_hub_names" {
  description = "Full resource name of each tunnel-token hub, for the bindings that hold its trust rule."
  value       = { for k, h in google_service_account.tunnel_token_hub : k => h.name }
}

output "posthog_token_writer" {
  description = "The federated identity that runs _posthog-live-apply.yml, which writes the PostHog project token to each environment's secret after the apply. No service account stands in between, as for its state access."
  value       = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.apply_entry/${one(local.posthog_apply_entries)}"
}

output "setup_plan" {
  description = "Service account the _setup roots are planned as."
  value       = google_service_account.setup_plan.email
}

output "setup_plan_principal" {
  description = "The setup plan identity, in the form IAM deny policies expect."
  value       = "principal://iam.googleapis.com/projects/-/serviceAccounts/${google_service_account.setup_plan.email}"
}

output "bootstrap_admin" {
  description = "Service account _setup-apply.yml runs as."
  value       = local.bootstrap_admin
}

output "plan_store_bucket" {
  description = "Bucket the plan workflows upload the full plan to."
  value       = module.plan_store.name
}

output "backend_deploy_hub" {
  value = google_service_account.backend_deploy_hub.email
}

output "backend_deploy_hub_name" {
  description = "Full resource name of the backend deploy hub, for the binding that holds its trust rule."
  value       = google_service_account.backend_deploy_hub.name
}

output "hub_trust_role" {
  description = "Custom role that lets an apply spoke set who may become a hub."
  value       = google_project_iam_custom_role.hub_trust_editor.id
}

output "platform_repository" {
  description = "owner/name of this repository, as the trust rules spell it."
  value       = local.platform_repo
}

output "backend_repository" {
  description = "owner/name of the application repository, as the trust rules spell it."
  value       = local.backend_repo
}
