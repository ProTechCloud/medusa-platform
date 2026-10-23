output "zone_id" {
  value = var.zone_id
}

# The value, so it can be read once and pasted into GitHub:
#
#   terraform output -raw plan_token
#
# Marked sensitive, which keeps it out of the plan and apply logs. It does not
# keep it out of the state file — `sensitive` masks output, it does not encrypt
# storage. The state is what protects it: CMEK-encrypted, in the management
# bucket, under a prefix no CI identity can read.
output "plan_token" {
  description = "Read-only token for plan jobs. Goes into the CLOUDFLARE_PLAN_TOKEN repository secret."
  value       = cloudflare_api_token.plan.value
  sensitive   = true
}

# Not secret, and worth having: an id is what an audit log entry names, so this
# is how you tell which token did something.
output "plan_token_id" {
  value = cloudflare_api_token.plan.id
}
