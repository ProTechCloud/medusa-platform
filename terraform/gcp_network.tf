resource "google_compute_network" "main" {
  project                 = var.gcp_project_id
  name                    = "${local.name_prefix}-net"
  auto_create_subnetworks = false

  depends_on = [google_project_service.enabled]
}

resource "google_compute_subnetwork" "main" {
  project       = var.gcp_project_id
  name          = "${local.name_prefix}-subnet"
  region        = var.gcp_region
  network       = google_compute_network.main.id
  ip_cidr_range = "10.10.0.0/24"

  # Needed for IAP SSH logs to be useful.
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# The ONLY inbound rule. 35.235.240.0/20 is Google's IAP forwarding range —
# traffic arrives already authenticated by IAM, so port 22 is never exposed
# to the public internet.
resource "google_compute_firewall" "iap_ssh" {
  project = var.gcp_project_id
  name    = "${local.name_prefix}-allow-iap-ssh"
  network = google_compute_network.main.name

  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["35.235.240.0/20"]
  target_tags   = [local.name_prefix]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Belt and braces: everything else inbound is dropped explicitly, so a stray
# default-allow rule elsewhere cannot open the box.
resource "google_compute_firewall" "deny_all_ingress" {
  project = var.gcp_project_id
  name    = "${local.name_prefix}-deny-ingress"
  network = google_compute_network.main.name

  direction     = "INGRESS"
  priority      = 65000
  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.name_prefix]

  deny {
    protocol = "all"
  }
}
