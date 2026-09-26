output "a_ps02sn_buckets" {
  description = "Summary of provisioned Tier A (Synology ps02sn) buckets"
  value = {
    for k, v in garage_bucket.a_ps02sn : k => {
      id           = v.id
      global_alias = v.global_alias
    }
  }
}

output "b_cl01tl_buckets" {
  description = "Summary of provisioned Tier B (Cluster cl01tl) buckets"
  value = {
    for k, v in garage_bucket.b_cl01tl : k => {
      id           = v.id
      global_alias = v.global_alias
    }
  }
}

output "c_ps10rp_buckets" {
  description = "Summary of provisioned Tier C (Raspberry Pi ps10rp) buckets"
  value = {
    for k, v in garage_bucket.c_ps10rp : k => {
      id           = v.id
      global_alias = v.global_alias
    }
  }
}

output "d_cs01bb_buckets" {
  description = "Summary of provisioned Tier D (Backblaze B2 cs01bb) buckets"
  value = {
    for k, v in aws_s3_bucket.d_cs01bb : k => {
      id  = v.id
      arn = v.arn
    }
  }
}
