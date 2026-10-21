# ---------- role 1: read-only ----------
# `viewer` is the broad "see everything" role. It deliberately does not grant
# secretmanager.versions.access, but it does grant enough adjacent permissions
# that relying on that absence is a bet on Google never widening the role. The
# deny policy below turns it into a guarantee.
resource "google_project_iam_member" "read_only" {
  project = var.project_id
  role    = "roles/viewer"
  member  = var.group
}

# Deny beats allow, always and everywhere. Even if someone later grants this
# group secretAccessor by hand, reading a value stays refused until this
# policy is edited — and editing it shows up as a diff here.
resource "google_iam_deny_policy" "no_secret_values" {
  parent       = urlencode("cloudresourcemanager.googleapis.com/projects/${var.project_id}")
  name         = "medusa-developers-no-secret-values"
  display_name = "Developers may see that a secret exists, never its value"

  rules {
    deny_rule {
      denied_principals = [replace(var.group, "group:", "principalSet://goog/group/")]
      denied_permissions = [
        "secretmanager.googleapis.com/versions.access",
      ]
    }
  }
}

# ---------- role 2: server-access ----------
# Granted separately so it can be given to some people and not others, and so
# revoking shell access does not also remove the ability to read dashboards.

# The tunnel itself, narrowed to one instance. Without the condition this
# would cover every current and future instance in the project.
resource "google_project_iam_member" "iap_tunnel" {
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = var.group

  # IAP names its resources on its own path, with the project NUMBER and the
  # instance's numeric id — not the Compute path with the project id and the
  # instance name. A condition written in the Compute form matches nothing, so
  # the grant silently allows no tunnel at all.
  #
  # The numeric instance id is unknown here: this root runs before the VM
  # exists, and the id changes whenever the VM is replaced. The condition
  # therefore pins everything up to the zone. One zone holds one API instance
  # by design; a second VM added there would be reachable, which is the cost
  # of not being able to name the instance in advance.
  condition {
    title      = "only instances in the api zone"
    expression = "resource.name.startsWith('projects/${var.project_number}/iap_tunnel/zones/${var.zone}/instances/')"
  }
}

# Reaching the port is not the same as being let in. OS Login makes the shell
# itself an IAM decision, so removing someone from the group closes their
# session path without touching any key file on the box.
resource "google_project_iam_member" "os_login" {
  project = var.project_id
  role    = "roles/compute.osLogin"
  member  = var.group
}
