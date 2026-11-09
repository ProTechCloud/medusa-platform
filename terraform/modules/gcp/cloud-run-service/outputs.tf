output "name" {
  description = "Service name, as the load balancer's NEG and the deploy refer to it."
  value       = google_cloud_run_v2_service.this.name
}

output "max_instances" {
  description = "The scaling ceiling, for the saturation alert."
  value       = var.max_instances
}
