# Watching the service, in four alerts: is it answering, and are the three
# resources that make it stop answering running out.
#
# Everything here is free-tier: alerting policies and notification channels
# cost nothing, and uptime checks are billed per execution with a monthly
# allowance one check every five minutes does not approach.

# One channel, reused by every policy. A policy with no channel is a dashboard
# nobody looks at, so the channel is created here rather than left to the
# console — which is also what keeps the recipient reviewable in a diff.
resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "medusa ${var.environment} alerts"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }

  user_labels = var.labels
}

# The check runs against the public hostname, not the instance. The firewall
# denies every inbound route except the IAP range, so there is nothing for a
# checker to reach directly — and a check that bypassed Cloudflare would stay
# green through exactly the failures a user would see, a broken tunnel or an
# expired certificate among them.
resource "google_monitoring_uptime_check_config" "api" {
  project      = var.project_id
  display_name = "medusa ${var.environment} api"
  timeout      = "10s"
  period       = var.period

  http_check {
    request_method = "GET"
    path           = "/health"
    port           = 443
    use_ssl        = true

    # Fail on a certificate the browser would reject, rather than reporting a
    # site nobody can open as healthy.
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"

    labels = {
      project_id = var.project_id
      host       = var.hostname
    }
  }

  user_labels = var.labels
}

# ---------- is it answering ----------
# Counting failures across regions rather than alerting on the first one. Each
# check runs from several of Google's regions, and one region failing on its
# own is usually that region's path to the edge, not the service. Requiring
# more than one over a twenty-minute window is Google's own recommended shape
# for this metric.
resource "google_monitoring_alert_policy" "api_down" {
  project      = var.project_id
  display_name = "medusa ${var.environment}: API is not answering /health"
  combiner     = "OR"

  conditions {
    display_name = "uptime check failing from more than one region"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\"",
        "resource.type=\"uptime_url\"",
        "metric.label.check_id=\"${google_monitoring_uptime_check_config.api.uptime_check_id}\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "60s"

      aggregations {
        alignment_period     = "1200s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.*"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  user_labels           = var.labels

  documentation {
    mime_type = "text/markdown"
    content   = "The API stopped answering `/health` through Cloudflare. Follow **API down** in `docs/runbooks.md`: the first question is whether the VM is running or the tunnel is down, and the two have different fixes."
  }

  # Close an open incident after a week if the metric never recovers and
  # nobody acknowledged it, so a stale incident does not suppress the next one.
  alert_strategy {
    auto_close = "604800s"
  }
}

# ---------- is it running out of something ----------
# CPU comes from the hypervisor, which reports it whatever the guest is doing.
# Memory and disk can only be seen from inside, and come from the agent
# Container-Optimized OS runs when google-monitoring-enabled is set on the
# instance — which is why the instance also holds roles/monitoring.metricWriter
# and the project has monitoring.googleapis.com enabled. Without either, these
# two policies would sit there and never fire.
#
# Ten minutes above the line, not one sample: a deploy pegs the CPU while it
# pulls an image, and an alert that fires on that is an alert people learn to
# ignore.
resource "google_monitoring_alert_policy" "cpu_high" {
  project      = var.project_id
  display_name = "medusa ${var.environment}: VM CPU is high"
  combiner     = "OR"

  conditions {
    display_name = "cpu above ${var.cpu_threshold * 100}% for ten minutes"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type=\"compute.googleapis.com/instance/cpu/utilization\"",
        "resource.type=\"gce_instance\"",
        "metric.label.instance_name=\"${var.instance_name}\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = var.cpu_threshold
      duration        = "600s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  user_labels           = var.labels

  documentation {
    mime_type = "text/markdown"
    content   = "The API VM has been busy for ten minutes. Sustained load on one small instance is either real traffic or a loop in the application; `docs/runbooks.md` covers reaching the box to look."
  }

  alert_strategy {
    auto_close = "604800s"
  }
}

resource "google_monitoring_alert_policy" "memory_high" {
  project      = var.project_id
  display_name = "medusa ${var.environment}: VM memory is high"
  combiner     = "OR"

  conditions {
    display_name = "memory above ${var.memory_threshold}% for ten minutes"

    # The metric reports one series, in percent, already net of buffers, cache
    # and slab — so this is memory the application cannot get back, not memory
    # Linux is merely holding on to.
    condition_threshold {
      filter = join(" AND ", [
        "metric.type=\"compute.googleapis.com/guest/memory/percent_used\"",
        "resource.type=\"gce_instance\"",
        "metric.label.instance_name=\"${var.instance_name}\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = var.memory_threshold
      duration        = "600s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  user_labels           = var.labels

  documentation {
    mime_type = "text/markdown"
    content   = "Memory on the API VM has been high for ten minutes. The box is small and the kernel will kill the container before it kills itself, so this usually arrives shortly before the API stops answering."
  }

  alert_strategy {
    auto_close = "604800s"
  }
}

resource "google_monitoring_alert_policy" "disk_high" {
  project      = var.project_id
  display_name = "medusa ${var.environment}: VM disk is filling up"
  combiner     = "OR"

  conditions {
    display_name = "${var.disk_device} above ${var.disk_threshold}% for ten minutes"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type=\"compute.googleapis.com/guest/disk/percent_used\"",
        "resource.type=\"gce_instance\"",
        "metric.label.instance_name=\"${var.instance_name}\"",
        "metric.label.device_name=\"${var.disk_device}\"",
      ])

      comparison      = "COMPARISON_GT"
      threshold_value = var.disk_threshold
      duration        = "600s"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
  user_labels           = var.labels

  documentation {
    mime_type = "text/markdown"
    content   = "The writable partition on the API VM is filling up. On this box that is almost always old container images from previous deploys."
  }

  alert_strategy {
    auto_close = "604800s"
  }
}
