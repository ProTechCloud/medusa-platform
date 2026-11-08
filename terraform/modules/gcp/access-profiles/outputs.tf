# What each human access profile grants, in one place, so the group, the
# administrator and the member list cannot drift apart.
output "roles" {
  description = "The roles each access profile grants on a project."
  value = {
    read_only = ["roles/viewer"]

    # editor does everything to resources and projectIamAdmin adds managing who
    # has access: owner without deleting the project or moving its billing.
    # secretAccessor so a recovery can read a value.
    administration = [
      "roles/editor",
      "roles/resourcemanager.projectIamAdmin",
      "roles/secretmanager.secretAccessor",
    ]

    # For a person who needs nothing else.
    logs = ["roles/logging.viewer"]
  }
}
