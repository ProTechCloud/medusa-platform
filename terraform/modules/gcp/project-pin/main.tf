# Credentials reach Terraform through the environment — a workflow input, an
# impersonation flag, an exported variable. Any of those can point at the wrong
# environment while the code still says `stg`. Reading back who we actually
# are, and refusing to continue on a mismatch, is the only check that does not
# trust the same thing it is verifying.

data "google_client_openid_userinfo" "current" {}

locals {
  email = data.google_client_openid_userinfo.current.email

  # Service account emails embed their project: name@PROJECT.iam.gserviceaccount.com
  is_service_account = can(regex("\\.iam\\.gserviceaccount\\.com$", local.email))
  credential_project = local.is_service_account ? regex("@([^.]+)\\.iam\\.gserviceaccount\\.com$", local.email)[0] : null

  matches = local.is_service_account ? local.credential_project == var.expected_project_id : var.allow_user_credentials
}

resource "terraform_data" "pin" {
  # Evaluated during plan, so a mismatch stops the run before the provider is
  # asked to change anything.
  lifecycle {
    precondition {
      condition = local.matches
      error_message = local.is_service_account ? join("", [
        "Project pin failed. This root is pinned to '${var.expected_project_id}', ",
        "but the active credential (${local.email}) belongs to '${coalesce(local.credential_project, "unknown")}'. ",
        "Nothing was changed. Check which hub the workflow requested.",
        ]) : join("", [
        "Project pin failed. This root refuses human credentials, and the active ",
        "credential (${local.email}) is not a service account. CI roots must run ",
        "through the identity pool; only _setup roots are applied by a person.",
      ])
    }
  }
}
