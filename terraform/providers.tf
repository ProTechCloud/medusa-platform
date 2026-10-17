# Terraform does not read the gcloud CLI's active credential; it needs
# Application Default Credentials. With `gcp_impersonate_service_account` set,
# ADC is used only to mint a token for that SA — matching the impersonation
# the CLI is already configured for.
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
  zone    = var.gcp_zone
  # Must be null (not "") when unset — the provider rejects an empty string.
  impersonate_service_account = var.gcp_impersonate_service_account != "" ? var.gcp_impersonate_service_account : null
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "github" {
  owner = var.github_owner
  token = var.github_token
}
