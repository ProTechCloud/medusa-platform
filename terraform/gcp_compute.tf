data "google_compute_image" "cos" {
  family  = "cos-121-lts"
  project = "cos-cloud"
}

resource "google_compute_instance" "api" {
  project      = var.gcp_project_id
  name         = local.name_prefix
  machine_type = var.machine_type
  zone         = var.gcp_zone
  tags         = [local.name_prefix]
  labels       = local.common_labels

  boot_disk {
    initialize_params {
      image  = data.google_compute_image.cos.self_link
      size   = var.boot_disk_size_gb
      type   = "pd-standard"
      labels = local.common_labels
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id

    # Ephemeral address — no reserved/static IP. It exists purely for egress
    # (pulling images, dialing out to the Cloudflare edge). Nothing inbound
    # can use it: the firewall denies all ingress except the IAP range.
    access_config {
      network_tier = "STANDARD"
    }
  }

  service_account {
    email  = google_service_account.instance.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = {
    user-data                 = local.cloud_init
    google-logging-enabled    = "true"
    google-monitoring-enabled = "true"
    enable-oslogin            = "TRUE"
    block-project-ssh-keys    = "TRUE"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  # Cheapest posture: let the scheduler reclaim it, and bring it back on boot.
  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  # Replacing the box on every cloud-init tweak is correct — it is immutable
  # infrastructure, and CI re-deploys the image right after.
  lifecycle {
    create_before_destroy = false
  }

  depends_on = [
    google_secret_manager_secret_version.tunnel_token,
    google_secret_manager_secret_iam_member.instance_reads_token,
    google_artifact_registry_repository_iam_member.instance_pulls,
  ]
}
