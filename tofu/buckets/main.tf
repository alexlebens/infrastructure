# ==============================================================================
# 1. Primary S3 Storage: Tier A - Synology A (a_ps02sn)
# Heavy stores, bulk backups, Loki, Thanos, Prometheus, etc.
# ==============================================================================

resource "garage_bucket" "a_ps02sn" {
  provider     = garage.a_ps02sn
  for_each     = local.a_ps02sn_buckets
  global_alias = each.value.bucket_name
}

resource "garage_key" "a_ps02sn" {
  provider = garage.a_ps02sn
  for_each = local.a_ps02sn_buckets
  name     = "${each.value.bucket_name}-key"
}

resource "garage_bucket_key" "a_ps02sn" {
  provider      = garage.a_ps02sn
  for_each      = local.a_ps02sn_buckets
  bucket_id     = garage_bucket.a_ps02sn[each.key].id
  access_key_id = garage_key.a_ps02sn[each.key].access_key_id
  read          = true
  write         = true
  owner         = true
}

resource "aws_s3_bucket_cors_configuration" "a_ps02sn" {
  provider = aws.a_ps02sn
  for_each = local.cors_a_ps02sn_buckets
  bucket   = garage_bucket.a_ps02sn[each.key].global_alias

  cors_rule {
    allowed_headers = each.value.cors.allowed_headers
    allowed_methods = each.value.cors.allowed_methods
    allowed_origins = each.value.cors.allowed_origins
    expose_headers  = each.value.cors.expose_headers
    max_age_seconds = each.value.cors.max_age_seconds
  }
}

resource "aws_s3_bucket_website_configuration" "a_ps02sn" {
  provider = aws.a_ps02sn
  for_each = local.website_a_ps02sn_buckets
  bucket   = garage_bucket.a_ps02sn[each.key].global_alias

  index_document {
    suffix = each.value.website.index_document
  }

  error_document {
    key = each.value.website.error_document
  }
}

# ==============================================================================
# 2. Primary S3 Storage: Tier B - Cluster B (b_cl01tl)
# Low-latency, in-cluster lightweight app assets (Reactive Resume, Memos, etc.)
# ==============================================================================

resource "garage_bucket" "b_cl01tl" {
  provider     = garage.b_cl01tl
  for_each     = local.b_cl01tl_buckets
  global_alias = each.value.bucket_name
}

resource "garage_key" "b_cl01tl" {
  provider = garage.b_cl01tl
  for_each = local.b_cl01tl_buckets
  name     = "${each.value.bucket_name}-key"
}

resource "garage_bucket_key" "b_cl01tl" {
  provider      = garage.b_cl01tl
  for_each      = local.b_cl01tl_buckets
  bucket_id     = garage_bucket.b_cl01tl[each.key].id
  access_key_id = garage_key.b_cl01tl[each.key].access_key_id
  read          = true
  write         = true
  owner         = true
}

resource "aws_s3_bucket_cors_configuration" "b_cl01tl" {
  provider = aws.b_cl01tl
  for_each = local.cors_b_cl01tl_buckets
  bucket   = garage_bucket.b_cl01tl[each.key].global_alias

  cors_rule {
    allowed_headers = each.value.cors.allowed_headers
    allowed_methods = each.value.cors.allowed_methods
    allowed_origins = each.value.cors.allowed_origins
    expose_headers  = each.value.cors.expose_headers
    max_age_seconds = each.value.cors.max_age_seconds
  }
}

resource "aws_s3_bucket_website_configuration" "b_cl01tl" {
  provider = aws.b_cl01tl
  for_each = local.website_b_cl01tl_buckets
  bucket   = garage_bucket.b_cl01tl[each.key].global_alias

  index_document {
    suffix = each.value.website.index_document
  }

  error_document {
    key = each.value.website.error_document
  }
}

# ==============================================================================
# 3. Secondary S3 Storage: Tier C - Raspberry Pi (c_ps10rp)
# Storage node replication & secondary on-prem targets
# ==============================================================================

resource "garage_bucket" "c_ps10rp" {
  provider     = garage.c_ps10rp
  for_each     = local.c_ps10rp_buckets
  global_alias = each.value.bucket_name
}

resource "garage_key" "c_ps10rp" {
  provider = garage.c_ps10rp
  for_each = local.c_ps10rp_buckets
  name     = "${each.value.bucket_name}-key"
}

resource "garage_bucket_key" "c_ps10rp" {
  provider      = garage.c_ps10rp
  for_each      = local.c_ps10rp_buckets
  bucket_id     = garage_bucket.c_ps10rp[each.key].id
  access_key_id = garage_key.c_ps10rp[each.key].access_key_id
  read          = true
  write         = true
  owner         = true
}

# ==============================================================================
# 4. Offsite DR Storage: Tier D - Backblaze B2 (d_cs01bb)
# Cloud replica bucket creation and optional prune lifecycle policies
# ==============================================================================

resource "b2_bucket" "d_cs01bb" {
  for_each    = local.d_cs01bb_buckets
  bucket_name = each.value.backups.d_cs01bb.destination_bucket
  bucket_type = "allPrivate"

  dynamic "lifecycle_rules" {
    for_each = each.value.backups.d_cs01bb.prune.enabled ? [1] : []
    content {
      file_name_prefix              = ""
      days_from_uploading_to_hiding = tonumber(replace(each.value.backups.d_cs01bb.prune.age_to_prune, "d", ""))
      days_from_hiding_to_deleting  = 1
    }
  }

  lifecycle {
    ignore_changes = [
      bucket_type,
      file_lock_configuration,
      default_server_side_encryption,
    ]
  }
}

# ==============================================================================
# 5. OpenBao (Vault KV) Secrets Management
# Sync credentials directly to /garage/home-infra/<bucket> and /backblaze/home-infra/<bucket>
# ==============================================================================

resource "vault_kv_secret_v2" "a_ps02sn_credentials" {
  for_each = local.a_ps02sn_buckets
  mount    = "secret"
  name     = "garage/home-infra/${each.value.bucket_name}"

  data_json = jsonencode({
    ACCESS_KEY_ID     = garage_key.a_ps02sn[each.key].access_key_id
    ACCESS_SECRET_KEY = garage_key.a_ps02sn[each.key].secret_access_key
    ACCESS_REGION     = "garage"
  })
}

resource "vault_kv_secret_v2" "b_cl01tl_credentials" {
  for_each = local.b_cl01tl_buckets
  mount    = "secret"
  name     = "garage/home-infra/${each.value.bucket_name}"

  data_json = jsonencode({
    ACCESS_KEY_ID     = garage_key.b_cl01tl[each.key].access_key_id
    ACCESS_SECRET_KEY = garage_key.b_cl01tl[each.key].secret_access_key
    ACCESS_REGION     = "garage"
  })
}

resource "vault_kv_secret_v2" "c_ps10rp_credentials" {
  for_each = local.c_ps10rp_buckets
  mount    = "secret"
  name     = "garage/home-infra/${each.value.bucket_name}"

  data_json = jsonencode({
    ACCESS_KEY_ID     = garage_key.c_ps10rp[each.key].access_key_id
    ACCESS_SECRET_KEY = garage_key.c_ps10rp[each.key].secret_access_key
    ACCESS_REGION     = "garage"
  })
}

# When Tier D (Backblaze B2) is enabled, ensure /backblaze/home-infra/<bucket> is stored
resource "vault_kv_secret_v2" "d_cs01bb_credentials" {
  for_each = {
    for k, v in local.d_cs01bb_buckets : k => v
    if var.backblaze_d_cs01bb_access_key_id != ""
  }
  mount = "secret"
  name  = "backblaze/home-infra/${each.value.bucket_name}"

  data_json = jsonencode({
    AWS_ACCESS_KEY_ID     = var.backblaze_d_cs01bb_access_key_id
    AWS_SECRET_ACCESS_KEY = var.backblaze_d_cs01bb_secret_access_key
    AWS_REGION            = var.backblaze_d_cs01bb_region
  })
}
