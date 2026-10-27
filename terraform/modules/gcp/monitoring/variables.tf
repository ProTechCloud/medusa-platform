variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "instance_name" {
  description = "VM the host alerts watch. Every guest metric carries it as a metric label, so this is how an alert names one box rather than the project."
  type        = string
}

variable "hostname" {
  description = "Public hostname the uptime check calls. The VM has no inbound route of its own, so the check goes through Cloudflare, which is also what a user's request traverses."
  type        = string
}

variable "alert_email" {
  description = "Address every alert is sent to. Comes from the administrator declared in org/gcp/_setup, so the person who owns changes made outside CI is the person who hears about an outage."
  type        = string
}

variable "labels" {
  description = "Labels applied to each policy and to the check."
  type        = map(string)
  default     = {}
}

variable "period" {
  description = "How often the uptime check runs, from each of Google's regions."
  type        = string
  default     = "300s"
}

variable "cpu_threshold" {
  description = "CPU utilisation that counts as high, as a fraction. The hypervisor reports this metric between 0 and 1, not as a percentage."
  type        = number
  default     = 0.8
}

variable "memory_threshold" {
  description = "Memory in use that counts as high, as a percentage."
  type        = number
  default     = 85
}

variable "disk_threshold" {
  description = "Disk in use that counts as high, as a percentage."
  type        = number
  default     = 85
}

# Container-Optimized OS mounts its root filesystem read-only and essentially
# full by design, and the guest agent reports every mounted device. An alert
# that did not name a device would therefore fire on the first sample and never
# clear. The one device worth watching is the stateful partition, which is
# where images, container writes and logs land.
#
# Confirm the label value once the VM is running — Metrics Explorer on
# compute.googleapis.com/guest/disk/percent_used lists the device names this
# instance actually reports — and change this input if it differs.
variable "disk_device" {
  description = "Device label of the writable partition the disk alert watches."
  type        = string
  default     = "sda1"
}
