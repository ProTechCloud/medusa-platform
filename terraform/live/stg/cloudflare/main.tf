# The environment's shared values: its name, zone and API hostname (README,
# "Shared values").
module "shared" {
  source = "../shared"
}

locals {
  # The API's hostname on the load balancer, DNS-only (api.tf).
  hostname = module.shared.api_hostname

  # The hostnames whose A record this root publishes, from the GCP root's
  # handoff: each joins once it serves TLS and stays.
  published_hosts = local.gcp == null ? [] : local.gcp.published_hosts
}
