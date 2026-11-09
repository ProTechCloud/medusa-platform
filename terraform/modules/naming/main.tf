# The names an environment is known by, derived once from two facts: which
# environment, and the zone. No provider, no state: the environment's `shared/`
# module calls this and every root in that environment reads the result.
locals {
  # prd is the bare zone; every other environment is a subdomain of it.
  host_prefix = var.environment == "prd" ? "" : "${var.environment}."
}

output "environment" {
  value = var.environment
}

output "zone" {
  value = var.zone
}

output "name" {
  description = "Resource name prefix: `medusa-stg`."
  value       = "medusa-${var.environment}"
}

output "api_hostname" {
  description = "Public hostname of the API: `api.stg.<zone>`, `api.<zone>` in prd."
  value       = "api.${local.host_prefix}${var.zone}"
}

output "labels" {
  description = "Base labels. `component` is added at each module call."
  value = {
    env          = var.environment
    "managed-by" = "terraform"
  }
}
