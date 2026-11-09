module "registry" {
  source = "../../../modules/gcp/artifact-registry"

  project_id  = var.project_id
  name        = local.name
  location    = var.region
  description = "Container images for medusa (${module.shared.environment})"
  labels      = merge(local.labels, { component = "registry" })

  keep_recent_versions = 30
}
