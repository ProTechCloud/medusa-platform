# ---------- what the application's deploy identity may touch ----------
# Scoped to this registry and this service. The deploy can publish an image
# and roll the API's service onto it.
resource "google_artifact_registry_repository_iam_member" "deploy_pushes" {
  project    = var.project_id
  location   = module.registry.location
  repository = module.registry.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${local.setup.deploy_spoke}"
}

# run.developer on the service lets the deploy create a revision, and also
# change anything else in the template or delete the service; it carries no
# setIamPolicy. Image-only is the deploy script's discipline: Terraform ignores
# only the image, so any other change shows as drift and the next apply reverts
# it.
resource "google_cloud_run_v2_service_iam_member" "deploy_rolls_out_api" {
  project  = var.project_id
  location = var.region
  name     = module.api_service.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${local.setup.deploy_spoke}"
}
