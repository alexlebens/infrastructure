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

      # Target normalization: supports "a" / "a_ps02sn", "b" / "b_cl01tl", "c" / "c_ps10rp", "d" / "d_cs01bb"
      target = (
        contains(["a", "a_ps02sn", "synology-a", "synology_a"], try(cfg.target, "b")) ? "a_ps02sn" :
        contains(["b", "b_cl01tl", "cluster-b", "cluster_b"], try(cfg.target, "b")) ? "b_cl01tl" :
        contains(["c", "c_ps10rp"], try(cfg.target, "b")) ? "c_ps10rp" :
        contains(["d", "d_cs01bb", "backblaze"], try(cfg.target, "b")) ? "d_cs01bb" :
        try(cfg.target, "b_cl01tl")
      )

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
        # Tier A: Synology NAS (a_ps02sn)
        a_ps02sn = {
          enabled = coalesce(
            try(cfg.backups.a.enabled, null),
            try(cfg.backups.a_ps02sn.enabled, null),
            try(cfg.backups.synology_a.enabled, null),
            false
          )
          schedule = coalesce(
            try(cfg.backups.a.schedule, null),
            try(cfg.backups.a_ps02sn.schedule, null),
            try(cfg.backups.synology_a.schedule, null),
            "0 3 * * *"
          )
          destination_bucket = coalesce(
            try(cfg.backups.a.destination.bucketName, null),
            try(cfg.backups.a_ps02sn.destination.bucketName, null),
            try(cfg.backups.synology_a.destination.bucketName, null),
            try(cfg.bucketName, null),
            app
          )
        }

        # Tier B: Talos K8s cluster (b_cl01tl)
        b_cl01tl = {
          enabled = coalesce(
            try(cfg.backups.b.enabled, null),
            try(cfg.backups.b_cl01tl.enabled, null),
            try(cfg.backups.cluster_b.enabled, null),
            false
          )
          schedule = coalesce(
            try(cfg.backups.b.schedule, null),
            try(cfg.backups.b_cl01tl.schedule, null),
            try(cfg.backups.cluster_b.schedule, null),
            "0 1 * * *"
          )
          destination_bucket = coalesce(
            try(cfg.backups.b.destination.bucketName, null),
            try(cfg.backups.b_cl01tl.destination.bucketName, null),
            try(cfg.backups.cluster_b.destination.bucketName, null),
            try(cfg.bucketName, null),
            app
          )
        }

        # Tier C: Raspberry Pi (c_ps10rp)
        c_ps10rp = {
          enabled = coalesce(
            try(cfg.backups.c.enabled, null),
            try(cfg.backups.c_ps10rp.enabled, null),
            false
          )
          schedule = coalesce(
            try(cfg.backups.c.schedule, null),
            try(cfg.backups.c_ps10rp.schedule, null),
            "0 4 * * *"
          )
          destination_bucket = coalesce(
            try(cfg.backups.c.destination.bucketName, null),
            try(cfg.backups.c_ps10rp.destination.bucketName, null),
            try(cfg.bucketName, null),
            app
          )
        }

        # Tier D: Backblaze B2 (d_cs01bb)
        d_cs01bb = {
          enabled = coalesce(
            try(cfg.backups.d.enabled, null),
            try(cfg.backups.d_cs01bb.enabled, null),
            try(cfg.backups.backblaze.enabled, null),
            false
          )
          schedule = coalesce(
            try(cfg.backups.d.schedule, null),
            try(cfg.backups.d_cs01bb.schedule, null),
            try(cfg.backups.backblaze.schedule, null),
            "0 2 * * *"
          )
          destination_bucket = coalesce(
            try(cfg.backups.d.destination.bucketName, null),
            try(cfg.backups.d_cs01bb.destination.bucketName, null),
            try(cfg.backups.backblaze.destination.bucketName, null),
            try(cfg.bucketName, null),
            app
          )
          prune = {
            enabled = coalesce(
              try(cfg.backups.d.prune.enabled, null),
              try(cfg.backups.d_cs01bb.prune.enabled, null),
              try(cfg.backups.backblaze.prune.enabled, null),
              false
            )
            age_to_prune = coalesce(
              try(cfg.backups.d.prune.ageToPrune, null),
              try(cfg.backups.d_cs01bb.prune.ageToPrune, null),
              try(cfg.backups.backblaze.prune.ageToPrune, null),
              "90d"
            )
          }
        }
      }
    }
  }

  # Filter buckets by placement tier (primary target or backup destination)
  a_ps02sn_buckets = {
    for k, v in local.buckets : k => v if v.target == "a_ps02sn" || v.backups.a_ps02sn.enabled
  }

  b_cl01tl_buckets = {
    for k, v in local.buckets : k => v if v.target == "b_cl01tl" || v.backups.b_cl01tl.enabled
  }

  c_ps10rp_buckets = {
    for k, v in local.buckets : k => v if v.target == "c_ps10rp" || v.backups.c_ps10rp.enabled
  }

  # Buckets requiring Tier D (Backblaze B2 cs01bb) offsite replication
  d_cs01bb_buckets = {
    for k, v in local.buckets : k => v if v.backups.d_cs01bb.enabled
  }

  # Buckets with CORS enabled
  cors_a_ps02sn_buckets = {
    for k, v in local.a_ps02sn_buckets : k => v if v.cors.enabled
  }

  cors_b_cl01tl_buckets = {
    for k, v in local.b_cl01tl_buckets : k => v if v.cors.enabled
  }

  # Buckets with Website enabled
  website_a_ps02sn_buckets = {
    for k, v in local.a_ps02sn_buckets : k => v if v.website.enabled
  }

  website_b_cl01tl_buckets = {
    for k, v in local.b_cl01tl_buckets : k => v if v.website.enabled
  }
}
