locals {
  platform_repo = "${var.github_owner}/${var.platform_repository}"
  backend_repo  = "${var.github_owner}/${var.backend_repository}"

  # Pinning the audience means a token minted for some other Google resource
  # cannot be replayed here, even if it is otherwise valid.
  audience = "https://github.com/${var.github_owner}"

  bootstrap_admin = "medusa-bootstrap@${var.management_project_id}.iam.gserviceaccount.com"
}
