variable "account_id" {
  description = "Cloudflare account that owns the tunnel."
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone the DNS records are published in."
  type        = string
}

variable "management_state_bucket" {
  description = "The management bucket, where the GCP root's handoff object for this one is (handoff.tf)."
  type        = string
}

variable "app_port" {
  description = <<-EOT
    Port the application listens on, on the origin's loopback interface.

    Stated here rather than read from the GCP root's state. It is a constant of
    the application, not an output of that stack — and reading it across roots
    created an ordering dependency that is not real: the Cloudflare plan would
    fail on every pull request until the GCP workload had been applied once.
  EOT
  type        = number
  default     = 8080
}
