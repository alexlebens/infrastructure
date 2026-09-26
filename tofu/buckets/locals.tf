locals {
  # Base directory where Helm charts are located
  helm_dir = "${path.root}/../../clusters/cl01tl/helm"

  # Find all values.yaml files across app charts
  values_files = fileset(local.helm_dir, "*/values.yaml")

  # Discover all charts with s3-bucket enabled
  discovered_s3_configs = {
    for f in local.values_files :
    split("/", f)[0] => yamldecode(file("${local.helm_dir}/${f}"))["s3-bucket"]
    if try(yamldecode(file("${local.helm_dir}/${f}"))["s3-bucket"].enabled, false)
  }

  # Normalize configuration with sane defaults
  buckets = {
    for app, cfg in local.discovered_s3_configs : app => {
      app_name    = app
      bucket_name = coalesce(try(cfg.bucketName, null), app)
      target      = coalesce(try(cfg.target, null), "cluster-b") # Primary storage target: "synology-a" or "cluster-b"

      website = {
        enabled        = try(cfg.website.enabled, false)
        index_document = try(cfg.website.indexDocument, "index.html")
        error_document = try(cfg.website.errorDocument, "error.html")
      }

      cors = {
        enabled         = try(cfg.cors.enabled, false)
        allowed_origins = try(cfg.cors.allowedOrigins, ["*"])
        allowed_methods = try(cfg.cors.allowedMethods, ["GET", "HEAD"])
        allowed_headers = try(cfg.cors.allowedHeaders, ["*"])
        expose_headers  = try(cfg.cors.exposeHeaders, ["ETag"])
        max_age_seconds = try(cfg.cors.maxAgeSeconds, 3600)
      }

      backups = {
        cluster_b = {
          enabled            = try(cfg.backups.cluster_b.enabled, false)
          schedule           = try(cfg.backups.cluster_b.schedule, "0 1 * * *")
          destination_bucket = coalesce(try(cfg.backups.cluster_b.destination.bucketName, null), try(cfg.bucketName, null), app)
        }
        backblaze = {
          enabled            = try(cfg.backups.backblaze.enabled, false)
          schedule           = try(cfg.backups.backblaze.schedule, "0 2 * * *")
          destination_bucket = coalesce(try(cfg.backups.backblaze.destination.bucketName, null), try(cfg.bucketName, null), app)
          prune = {
            enabled      = try(cfg.backups.backblaze.prune.enabled, false)
            age_to_prune = try(cfg.backups.backblaze.prune.ageToPrune, "90d")
          }
        }
      }
    }
  }

  # Filter buckets by primary placement tier
  synology_buckets = {
    for k, v in local.buckets : k => v if v.target == "synology-a"
  }

  cluster_b_buckets = {
    for k, v in local.buckets : k => v if v.target == "cluster-b"
  }

  # Buckets requiring Backblaze DR offsite replication
  backblaze_buckets = {
    for k, v in local.buckets : k => v if v.backups.backblaze.enabled
  }

  # Buckets with CORS enabled
  cors_synology_buckets = {
    for k, v in local.synology_buckets : k => v if v.cors.enabled
  }

  cors_cluster_b_buckets = {
    for k, v in local.cluster_b_buckets : k => v if v.cors.enabled
  }

  # Buckets with Website enabled
  website_synology_buckets = {
    for k, v in local.synology_buckets : k => v if v.website.enabled
  }

  website_cluster_b_buckets = {
    for k, v in local.cluster_b_buckets : k => v if v.website.enabled
  }
}
