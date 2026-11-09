# The names an environment is known by, derived once from two facts: which
# environment, and the zone. No provider, no state: the environment's `shared/`
# module calls this and every root in that environment reads the result.
locals {
  # prd is the bare zone; every other environment is a subdomain of it.
  host_prefix = var.environment == "prd" ? "" : "${var.environment}."
}
