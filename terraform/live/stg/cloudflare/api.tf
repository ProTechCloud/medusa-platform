# Proves control of the API's hostname to Certificate Manager, which issues the
# load balancer's certificate against it before the hostname resolves there.
# Permanent: renewals reuse it. Exists once the GCP root's handoff does.
locals {
  certificate_authorization = local.gcp == null ? null : lookup(local.gcp.certificate_dns_authorizations, local.hostname, null)
}

module "certificate_authorization" {
  source = "../../../modules/cloudflare/dns-record"
  count  = local.certificate_authorization == null ? 0 : 1

  zone_id  = var.zone_id
  hostname = trimsuffix(local.certificate_authorization.name, ".")
  type     = local.certificate_authorization.type
  target   = trimsuffix(local.certificate_authorization.data, ".")
  proxied  = false
  comment  = "medusa ${module.shared.environment} api certificate authorization — managed by terraform"
}

# The API's hostname, straight to the load balancer and DNS-only, so the
# balancer sees each client's own address, which a per-IP rate limit there
# needs. Exists once the handoff lists the hostname as published, so it never
# points at a balancer that cannot serve TLS for it yet.
module "api" {
  source = "../../../modules/cloudflare/dns-record"
  count  = contains(local.published_hosts, local.hostname) ? 1 : 0

  zone_id  = var.zone_id
  hostname = local.hostname
  type     = "A"
  target   = local.gcp.load_balancer_ip
  proxied  = false
  comment  = "medusa ${module.shared.environment} api — managed by terraform"
}
