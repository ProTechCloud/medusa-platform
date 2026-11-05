module "dns" {
  source = "../../../modules/cloudflare/dns-record"

  zone_id  = var.zone_id
  hostname = local.hostname
  target   = module.tunnel.cname_target
  comment  = "medusa ${var.environment} — managed by terraform"
}
