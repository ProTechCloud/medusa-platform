# Who may become this environment's hubs. Each entry is the complete set of
# claims that must match at the same time, with no wildcards. Authoritative: an
# entry not written here is removed at the next apply.
locals {
  apply_entry   = "principalSet://iam.googleapis.com/${local.setup.workload_identity_pool}/attribute.apply_entry"
  platform_repo = local.setup.platform_repository
}

# The tunnel-token step runs directly in the deploy workflow rather than through
# a shared one, so its job_workflow_ref names that file. One hub per environment:
# a shared hub would let a stg deploy overwrite production's tunnel secret.
#
# prd names a workflow that does not exist yet: prd is planned and never applied,
# so nothing matches this entry today.
resource "google_service_account_iam_binding" "tunnel_token_hub" {
  service_account_id = local.setup.tunnel_token_hub_name
  role               = "roles/iam.workloadIdentityUser"
  members            = ["${local.apply_entry}/${local.platform_repo}|${local.platform_repo}/.github/workflows/prd-cd.yml|prd|refs/heads/dev"]
}
