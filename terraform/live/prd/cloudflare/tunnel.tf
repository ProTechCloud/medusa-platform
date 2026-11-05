module "tunnel" {
  source = "../../../modules/cloudflare/tunnel"

  account_id = var.account_id
  name       = "medusa-${var.environment}"
  hostname   = local.hostname
  app_port   = var.app_port
}
