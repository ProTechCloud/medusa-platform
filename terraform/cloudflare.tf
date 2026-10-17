# A named tunnel. The instance dials out to Cloudflare and holds the connection
# open, so the origin needs no inbound rule, no static IP and no open port.
resource "random_password" "tunnel_secret" {
  length  = 64
  special = false
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "api" {
  account_id    = var.cloudflare_account_id
  name          = local.name_prefix
  tunnel_secret = base64encode(random_password.tunnel_secret.result)
  config_src    = "cloudflare"
}

# Ingress is evaluated top-down; the catch-all 404 must stay last.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "api" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.api.id

  config = {
    ingress = [
      {
        hostname = local.hostname
        service  = "http://127.0.0.1:${var.app_port}"
        origin_request = {
          connect_timeout   = 10
          no_happy_eyeballs = false
        }
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

# Proxied CNAME to the tunnel. Cloudflare terminates TLS at the edge.
resource "cloudflare_dns_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = local.hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.api.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
  comment = "Managed by Terraform — ${local.name_prefix} tunnel"
}

# The scoped credential the instance uses to register with the tunnel.
# Never written to disk here; it goes straight into Secret Manager.
data "cloudflare_zero_trust_tunnel_cloudflared_token" "api" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.api.id
}
