variable "project_id" { type = string }
variable "name" {
  type        = string
  description = "Name prefix for every resource here, e.g. `medusa-stg`. Also the network tag the firewall rules target."
}
variable "region" { type = string }
variable "zone" { type = string }
variable "environment" { type = string }

variable "machine_type" {
  type        = string
  default     = "e2-micro"
  description = "e2-micro in us-central1/us-west1/us-east1 is covered by the always-free tier."
}

variable "boot_disk_size_gb" {
  type        = number
  default     = 10
  description = "The free tier covers 30 GB-month of pd-standard across the project."
}

variable "subnet_cidr" {
  type        = string
  default     = "10.10.0.0/24"
  description = "Private range for the subnet. Nothing routes to it from outside."
}

variable "app_port" {
  type        = number
  description = "Port the application listens on. Published on the loopback only; the connector reaches it from inside the box."
}

variable "cloudflared_image" {
  type        = string
  default     = "cloudflare/cloudflared:2026.10.4@sha256:c6c7ae1d5dfdcb094ad344ed68ccffc26635c9c6be80965664c33baf064b0515"
  description = "Connector image, as tag@digest. The connector holds the tunnel token, so it runs only an image whose content is pinned: a tag alone can be moved upstream and would run at the next restart."

  validation {
    condition     = can(regex("^[^@]+:[^@:]+@sha256:[0-9a-f]{64}$", var.cloudflared_image))
    error_message = "cloudflared_image must be pinned as <image>:<tag>@sha256:<digest>."
  }
}

variable "tunnel_token_secret_id" {
  type        = string
  description = "Short id of the Secret Manager secret holding the tunnel token. The instance reads it at boot with its own identity, so the value is never in metadata and never in state."
}

variable "posthog_token_secret_id" {
  type        = string
  description = "Short id of the Secret Manager secret holding the PostHog project token. Read at boot like the tunnel token, so the value is never in metadata and never in state."
}

variable "artifact_registry_name" { type = string }
variable "artifact_registry_location" { type = string }

variable "bootstrap_image" {
  type        = string
  default     = "gcr.io/google-samples/hello-app:1.0"
  description = "Image the box runs until the first deploy replaces it, so the tunnel has a live origin the moment it boots instead of a connection refused."
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "service_account_email" {
  description = "Identity the VM runs as, created in the environment's _setup root."
  type        = string
}
