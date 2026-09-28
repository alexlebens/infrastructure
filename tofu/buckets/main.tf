# ==============================================================================
# Primary S3 Storage: Tier A - Synology A (a_ps02sn)
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

# ==============================================================================
# Primary S3 Storage: Tier B - Cluster B (b_cl01tl)
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

# ==============================================================================
# Secondary S3 Storage: Tier C - Raspberry Pi (c_ps10rp)
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
# Offsite DR Storage: Tier D - Backblaze B2 (d_cs01bb)
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

resource "b2_application_key" "d_cs01bb" {
  for_each     = local.d_cs01bb_buckets
  key_name     = "${each.value.backups.d_cs01bb.destination_bucket}-key"
  capabilities = ["listBuckets", "listFiles", "readFiles", "writeFiles", "deleteFiles"]
  bucket_id    = b2_bucket.d_cs01bb[each.key].id
}

# ==============================================================================
# OpenBao (Vault KV) Secrets Management
#
# Standardized Path Scheme: /<id>/<service>/keys/<dataset-id>
# - ps02sn/garage/keys/<dataset-id>
# - cl01tl/garage/keys/<dataset-id>
# - ps10rp/garage/keys/<dataset-id>
# - cs01bb/s3/keys/<dataset-id>
# Contains BUCKET_NAME, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION
# ==============================================================================

# --- Standardized Path: Tier A Synology NAS (ps02sn/garage/keys/<id>) ---
resource "vault_kv_secret_v2" "a_ps02sn_keys" {
  for_each = local.a_ps02sn_buckets
  mount    = "secret"
  name     = "ps02sn/garage/keys/${each.value.bucket_name}"

  data_json = jsonencode({
    BUCKET_NAME           = each.value.bucket_name
    AWS_ACCESS_KEY_ID     = garage_key.a_ps02sn[each.key].access_key_id
    AWS_SECRET_ACCESS_KEY = garage_key.a_ps02sn[each.key].secret_access_key
    AWS_REGION            = "garage"
  })
}

# --- Standardized Path: Tier B Talos Cluster (cl01tl/garage/keys/<id>) ---
resource "vault_kv_secret_v2" "b_cl01tl_keys" {
  for_each = local.b_cl01tl_buckets
  mount    = "secret"
  name     = "cl01tl/garage/keys/${each.value.bucket_name}"

  data_json = jsonencode({
    BUCKET_NAME           = each.value.bucket_name
    AWS_ACCESS_KEY_ID     = garage_key.b_cl01tl[each.key].access_key_id
    AWS_SECRET_ACCESS_KEY = garage_key.b_cl01tl[each.key].secret_access_key
    AWS_REGION            = "garage"
  })
}

# --- Standardized Path: Tier C Raspberry Pi (ps10rp/garage/keys/<id>) ---
resource "vault_kv_secret_v2" "c_ps10rp_keys" {
  for_each = local.c_ps10rp_buckets
  mount    = "secret"
  name     = "ps10rp/garage/keys/${each.value.bucket_name}"

  data_json = jsonencode({
    BUCKET_NAME           = each.value.bucket_name
    AWS_ACCESS_KEY_ID     = garage_key.c_ps10rp[each.key].access_key_id
    AWS_SECRET_ACCESS_KEY = garage_key.c_ps10rp[each.key].secret_access_key
    AWS_REGION            = "garage"
  })
}

# --- Standardized Path: Tier D Backblaze B2 (cs01bb/s3/keys/<id>) ---
resource "vault_kv_secret_v2" "d_cs01bb_keys" {
  for_each = local.d_cs01bb_buckets
  mount    = "secret"
  name     = "cs01bb/s3/keys/${each.value.bucket_name}"

  data_json = jsonencode({
    BUCKET_NAME           = each.value.backups.d_cs01bb.destination_bucket
    AWS_ACCESS_KEY_ID     = b2_application_key.d_cs01bb[each.key].application_key_id
    AWS_SECRET_ACCESS_KEY = b2_application_key.d_cs01bb[each.key].application_key
    AWS_REGION            = var.backblaze_d_cs01bb_region
  })
}

# ==============================================================================
# Removals
# ==============================================================================

removed {
  from = aws_s3_bucket_website_configuration.a_ps02sn["web-assets"]

  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_s3_bucket_website_configuration.b_cl01tl["web-assets"]

  lifecycle {
    destroy = false
  }
}
g
