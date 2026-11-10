# The environment's shared values: its name, zone and API hostname (README,
# "Shared values").
module "shared" {
  source = "../shared"
}

locals {
  # The API's hostname on the load balancer, DNS-only (api.tf).
  hostname = module.shared.api_hostname

  # The tunnel's, flat: api-stg-medusa.<apex>, not api.stg.medusa.<apex>.
  # Universal SSL covers the apex and one wildcard level only, so a three-level
  # proxied host has no edge certificate on the Free plan and fails the
  # handshake before any of this matters. Hyphens are free; Advanced
  # Certificate Manager is not.
  tunnel_hostname = "api-${module.shared.environment}-${module.shared.zone}"

  # The hostnames whose A record this root publishes, from the GCP root's
  # handoff: each joins once it serves TLS and stays.
  published_hosts = local.gcp == null ? [] : local.gcp.published_hosts
}
