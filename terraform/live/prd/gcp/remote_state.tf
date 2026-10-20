data "terraform_remote_state" "setup" {
  backend = "gcs"

  config = {
    bucket = var.management_state_bucket
    prefix = "${var.environment}/gcp/setup"
  }
}

locals {
  setup = data.terraform_remote_state.setup.outputs
  name  = "medusa-${var.environment}"

  labels = {
    service     = "medusa"
    environment = var.environment
    managed_by  = "terraform"
  }
}
