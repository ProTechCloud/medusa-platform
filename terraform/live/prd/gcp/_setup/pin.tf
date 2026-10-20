module "pin" {
  source = "../../../../modules/gcp/project-pin"

  expected_project_id    = var.project_id
  allow_user_credentials = true
}
