output "uptime_check_id" {
  description = "Short id of the check. It is what the uptime metric carries as check_id, so it is how you find the series behind an alert."
  value       = google_monitoring_uptime_check_config.api.uptime_check_id
}

output "notification_channel" {
  description = "Channel every policy here notifies."
  value       = google_monitoring_notification_channel.email.id
}
