module "tunnel" {
  source = "../../../modules/cloudflare/tunnel"

  account_id = var.account_id
  name       = "medusa-${module.shared.environment}"
  hostname   = local.tunnel_hostname
  app_port   = var.app_port
}
