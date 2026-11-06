module "registry" {
  source = "../../../modules/gcp/artifact-registry"

  project_id  = var.project_id
  name        = local.name
  location    = var.region
  description = "Container images for medusa (${var.environment})"
  labels      = merge(local.labels, { component = "registry" })
}
