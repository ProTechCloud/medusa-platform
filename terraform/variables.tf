# ---------- identity ----------

variable "gcp_project_id" {
  description = "GCP project that hosts the instance, registry and secrets."
  type        = string
}

variable "gcp_region" {
  description = "Region for Artifact Registry and regional resources."
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "Zone for the instance. us-central1-a keeps e2-micro in the free tier."
  type        = string
  default     = "us-central1-a"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit and Account:Tunnel:Edit."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account that owns the zone and the tunnel."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Zone ID for the apex domain."
  type        = string
}

variable "github_token" {
  description = "GitHub PAT with `repo` scope — writes the Actions secrets."
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub org or user that owns the repositories."
  type        = string
  default     = "fahlula"
}

variable "backend_repository" {
  description = "Repository that receives the deploy secrets."
  type        = string
  default     = "medusa-backend"
}

# ---------- naming ----------

variable "domain" {
  description = "Apex domain managed in Cloudflare."
  type        = string
  default     = "fabianalula.site"
}

variable "environment" {
  description = "Environment slug; becomes part of the hostname and resource names."
  type        = string
  default     = "stg"
}

variable "service" {
  description = "Service name; becomes the image and instance name."
  type        = string
  default     = "medusa-backend"
}

# ---------- sizing ----------

variable "machine_type" {
  description = "Smallest practical shape. e2-micro: 2 vCPU burst, 1 GB RAM."
  type        = string
  default     = "e2-micro"
}

variable "boot_disk_size_gb" {
  description = "Dedicated boot disk. 10 GB is the pd-standard floor that fits COS + images."
  type        = number
  default     = 10

  validation {
    condition     = var.boot_disk_size_gb >= 10
    error_message = "Container-Optimized OS needs at least 10 GB."
  }
}

variable "app_port" {
  description = "Port the container listens on behind the tunnel."
  type        = number
  default     = 8080
}

variable "gcp_impersonate_service_account" {
  description = <<-EOT
    Service account for Terraform to impersonate, e.g.
    admin-cli-sa@<project>.iam.gserviceaccount.com. Leave empty to use ADC
    directly. Requires `gcloud auth application-default login` either way.
  EOT
  type        = string
  default     = ""
}

variable "platform_repository" {
  description = "Repository holding this Terraform; its CI federates in to apply."
  type        = string
  default     = "medusa-platform"
}
