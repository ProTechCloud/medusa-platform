module "dns" {
  source = "../../../modules/cloudflare/dns-record"

  zone_id  = var.zone_id
  hostname = local.tunnel_hostname
  target   = module.tunnel.cname_target
  comment  = "medusa ${module.shared.environment} — managed by terraform"
}
