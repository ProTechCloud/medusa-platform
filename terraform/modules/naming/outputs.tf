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
