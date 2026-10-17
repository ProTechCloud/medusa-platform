locals {
  # api.stg.medusa.fabianalula.site
  hostname = "api.${var.environment}.medusa.${var.domain}"

  name_prefix = "${var.service}-${var.environment}"

  # Every GCP API this stack touches. Enabled before anything consumes them.
  gcp_services = [
    "compute.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "iap.googleapis.com",
    "oslogin.googleapis.com",
  ]

  common_labels = {
    service     = var.service
    environment = var.environment
    managed_by  = "terraform"
  }
}

locals {
  # `hello-world` stands in until the first CI deploy overwrites it, so the
  # tunnel has a live origin the moment the box boots.
  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml", {
    project_id      = var.gcp_project_id
    secret_id       = google_secret_manager_secret.tunnel_token.secret_id
    region          = var.gcp_region
    app_port        = var.app_port
    environment     = var.environment
    bootstrap_image = "gcr.io/google-samples/hello-app:1.0"
  })
}
