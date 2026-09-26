output "synology_buckets" {
  description = "Summary of provisioned Synology A buckets"
  value = {
    for k, v in garage_bucket.synology : k => {
      id           = v.id
      global_alias = v.global_alias
    }
  }
}

output "cluster_b_buckets" {
  description = "Summary of provisioned Cluster B buckets"
  value = {
    for k, v in garage_bucket.cluster_b : k => {
      id           = v.id
      global_alias = v.global_alias
    }
  }
}

output "backblaze_buckets" {
  description = "Summary of provisioned Backblaze DR buckets"
  value = {
    for k, v in aws_s3_bucket.backblaze : k => {
      id  = v.id
      arn = v.arn
    }
  }
}
