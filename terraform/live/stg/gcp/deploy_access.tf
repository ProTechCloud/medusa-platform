# ---------- what the application's deploy identity may touch ----------
# Scoped to this registry and this instance. The deploy can publish an image
# and restart the box; it cannot create a second instance to run something
# else, and it cannot read the tunnel token the box reads at boot.
resource "google_artifact_registry_repository_iam_member" "deploy_pushes" {
  project    = var.project_id
  location   = module.registry.location
  repository = module.registry.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${local.setup.deploy_spoke}"
}

resource "google_compute_instance_iam_member" "deploy_rolls_out" {
  project       = var.project_id
  zone          = var.zone
  instance_name = module.api.instance_name
  role          = "roles/compute.instanceAdmin.v1"
  member        = "serviceAccount:${local.setup.deploy_spoke}"
}


# The deploy reaches port 22 through the same tunnel, on the same one
# instance. Its sudo rights are project-level and stay in _setup; what it may
# point them at is this.
resource "google_iap_tunnel_instance_iam_member" "deploy_tunnels" {
  project  = var.project_id
  zone     = var.zone
  instance = module.api.instance_name
  role     = "roles/iap.tunnelResourceAccessor"
  member   = "serviceAccount:${local.setup.deploy_spoke}"
}
