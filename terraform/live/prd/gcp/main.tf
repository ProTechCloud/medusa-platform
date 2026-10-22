module "registry" {
  source = "../../../modules/gcp/artifact-registry"

  project_id  = var.project_id
  name        = local.name
  location    = var.region
  description = "Container images for medusa (${var.environment})"
  labels      = local.labels
}

# The container only. Terraform never learns the value: the deploy job fetches
# the token from Cloudflare and writes a new version under the writer
# identity, so the token is absent from this state file by construction
# rather than by redaction.
module "tunnel_token" {
  source = "../../../modules/gcp/secret"

  project_id  = var.project_id
  environment = var.environment
  domain      = "cloudflare"
  name        = "tunnel-token"
  location    = var.region
  kms_key     = local.setup.secrets_key
  labels      = local.labels
}

# The writer's entire reason to exist, scoped to this one secret. secretVersionAdder
# rather than secretAccessor: it may add a version, and cannot read one back.
resource "google_secret_manager_secret_iam_member" "writer_adds_versions" {
  project   = var.project_id
  secret_id = module.tunnel_token.secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = "serviceAccount:${local.setup.tunnel_token_writer}"
}

module "api" {
  source = "../../../modules/gcp/api-vm"

  project_id  = var.project_id
  name        = local.name
  region      = var.region
  zone        = var.zone
  environment = var.environment
  app_port    = var.app_port
  labels      = local.labels

  service_account_email      = local.setup.instance_service_account
  tunnel_token_secret_id     = module.tunnel_token.secret_id
  artifact_registry_name     = module.registry.name
  artifact_registry_location = module.registry.location
}

# ---------- the IAP tunnel, bound on the instance ----------
# Bound here and not in _setup for one reason: this is the root that creates
# the VM, so this is the only place that can name it. `instance` takes the
# name, not the numeric id, and referencing the resource means Terraform
# rewrites the binding whenever the VM is replaced.
#
# Binding on the instance is what makes the grant true to its description: a
# second VM in this zone is not reachable through it. A project-level grant
# conditioned on the zone would cover every instance there.
#
# No deploy binding here: the application deploys to stg and nowhere else, so
# prd has no deploy spoke to grant.
resource "google_iap_tunnel_instance_iam_member" "developers_tunnel" {
  project  = var.project_id
  zone     = var.zone
  instance = module.api.instance_name
  role     = "roles/iap.tunnelResourceAccessor"
  member   = local.setup.developer_group
}
