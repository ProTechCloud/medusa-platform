# The record for this hostname existed before this root did. The single-root
# Terraform this repository replaced created it on 17 October as a CNAME to its
# own tunnel, `medusa-backend-stg`, and the first apply here stopped on
# Cloudflare's 81053: "An A, AAAA, or CNAME record with that host already
# exists."
#
# Adopted rather than deleted by hand, so every change to it is a reviewed
# plan and the record keeps its id. Adopting it changes nothing: its target
# stays on the old tunnel until the cutover described at local.dns_target in
# main.tf.
#
# Once applied this block is a no-op, and it can be removed in any later change.
import {
  to = module.dns.cloudflare_dns_record.this
  id = "${var.zone_id}/c2dbf53c8083f7a0050058a70c945be6"
}
