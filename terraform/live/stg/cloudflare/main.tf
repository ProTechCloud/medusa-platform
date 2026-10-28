locals {
  # Flat, not api.stg.medusa.<domain>. Universal SSL covers the apex and one
  # wildcard level only, so a three-level host has no edge certificate on the
  # Free plan and fails the handshake before any of this matters. Hyphens are
  # free; Advanced Certificate Manager is not.
  hostname = "api-${var.environment}-medusa.${var.domain}"

  # Where the record points while stg moves off the old stack: the tunnel of
  # the Terraform this repository replaced, `medusa-backend-stg`, which is
  # still healthy and still serving.
  #
  # Two steps, not one. Pointing the record at the new tunnel in the same apply
  # that creates it would send traffic to a tunnel with no connector — the
  # tunnel token is written by a later job, and the connector only exists
  # after that. If that job failed, stg would stay down until a later run.
  # So this apply creates the tunnel and leaves the record alone; stg-cd
  # writes the token and the new connector comes up beside the old one.
  #
  # Once `medusa-stg` reports healthy, a separate change replaces this with
  # module.tunnel.cname_target, and that apply is the cutover.
  dns_target = "0e48b9b4-c01c-4b72-b22e-984e658fad9f.cfargotunnel.com"
}

module "tunnel" {
  source = "../../../modules/cloudflare/tunnel"

  account_id = var.account_id
  name       = "medusa-${var.environment}"
  hostname   = local.hostname
  app_port   = var.app_port
}

module "dns" {
  source = "../../../modules/cloudflare/dns-record"

  zone_id  = var.zone_id
  hostname = local.hostname
  target   = local.dns_target
  comment  = "medusa ${var.environment} — managed by terraform"
}
