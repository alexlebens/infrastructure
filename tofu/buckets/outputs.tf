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

output "b_garage_b_buckets" {
  description = "Summary of provisioned Tier B Target (garage-b) buckets"
  value = {
    for k, v in garage_bucket.b_garage_b : k => {
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
    for k, v in b2_bucket.d_cs01bb : k => {
      id          = v.id
      bucket_name = v.bucket_name
      bucket_type = v.bucket_type
    }
  }
}

output "instance_keys" {
  description = "Summary of Admin and Read key IDs across all Garage instances"
  value = {
    a_ps02sn = {
      admin_access_key_id = garage_key.a_ps02sn_admin.access_key_id
      read_access_key_id  = garage_key.a_ps02sn_read.access_key_id
    }
    b_cl01tl = {
      admin_access_key_id = garage_key.b_cl01tl_admin.access_key_id
      read_access_key_id  = garage_key.b_cl01tl_read.access_key_id
    }
    b_garage_b = {
      admin_access_key_id = garage_key.b_garage_b_admin.access_key_id
      read_access_key_id  = garage_key.b_garage_b_read.access_key_id
    }
    c_ps10rp = {
      admin_access_key_id = garage_key.c_ps10rp_admin.access_key_id
      read_access_key_id  = garage_key.c_ps10rp_read.access_key_id
    }
  }
}
