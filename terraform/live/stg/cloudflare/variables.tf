variable "zone_id" {
  description = "Cloudflare zone the DNS records are published in."
  type        = string
}

variable "management_state_bucket" {
  description = "The management bucket, where the GCP root's handoff object for this one is (handoff.tf)."
  type        = string
}
