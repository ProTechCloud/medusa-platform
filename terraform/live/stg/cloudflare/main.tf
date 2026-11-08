locals {
  # Flat, not api.stg.medusa.<domain>. Universal SSL covers the apex and one
  # wildcard level only, so a three-level host has no edge certificate on the
  # Free plan and fails the handshake before any of this matters. Hyphens are
  # free; Advanced Certificate Manager is not.
  hostname = "api-${var.environment}-medusa.${var.domain}"
}
