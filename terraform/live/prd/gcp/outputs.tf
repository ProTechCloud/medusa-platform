output "instance_name" {
  value = module.api.instance_name
}

output "app_port" {
  description = "Read by the Cloudflare root to build the tunnel's ingress rule."
  value       = var.app_port
}

output "tunnel_token_secret_id" {
  description = "Secret the deploy job writes the token into."
  value       = module.tunnel_token.secret_id
}

output "registry_url" {
  value = module.registry.url
}
