# ==============================================================================
# 1. Primary S3 Storage: Synology A (synology-a)
# Heavy stores, bulk backups, Loki, Thanos, Prometheus, etc.
# ==============================================================================

resource "garage_bucket" "synology" {
  provider     = garage.synology_a
  for_each     = local.synology_buckets
  global_alias = each.value.bucket_name
}

resource "garage_key" "synology" {
  provider = garage.synology_a
  for_each = local.synology_buckets
  name     = "${each.value.bucket_name}-key"
}

resource "garage_bucket_key" "synology" {
  provider      = garage.synology_a
  for_each      = local.synology_buckets
  bucket_id     = garage_bucket.synology[each.key].id
  access_key_id = garage_key.synology[each.key].access_key_id
  read          = true
  write         = true
  owner         = true
}

resource "aws_s3_bucket_cors_configuration" "synology" {
  provider = aws.synology_a
  for_each = local.cors_synology_buckets
  bucket   = garage_bucket.synology[each.key].global_alias

  cors_rule {
    allowed_headers = each.value.cors.allowed_headers
    allowed_methods = each.value.cors.allowed_methods
    allowed_origins = each.value.cors.allowed_origins
    expose_headers  = each.value.cors.expose_headers
    max_age_seconds = each.value.cors.max_age_seconds
  }
}

resource "aws_s3_bucket_website_configuration" "synology" {
  provider = aws.synology_a
  for_each = local.website_synology_buckets
  bucket   = garage_bucket.synology[each.key].global_alias

  index_document {
    suffix = each.value.website.index_document
  }

  error_document {
    key = each.value.website.error_document
  }
}

# ==============================================================================
# 2. Primary S3 Storage: Cluster B (cluster-b)
# Low-latency, in-cluster lightweight app assets (Reactive Resume, Memos, etc.)
# ==============================================================================

resource "garage_bucket" "cluster_b" {
  provider     = garage.cluster_b
  for_each     = local.cluster_b_buckets
  global_alias = each.value.bucket_name
}

resource "garage_key" "cluster_b" {
  provider = garage.cluster_b
  for_each = local.cluster_b_buckets
  name     = "${each.value.bucket_name}-key"
}

resource "garage_bucket_key" "cluster_b" {
  provider      = garage.cluster_b
  for_each      = local.cluster_b_buckets
  bucket_id     = garage_bucket.cluster_b[each.key].id
  access_key_id = garage_key.cluster_b[each.key].access_key_id
  read          = true
  write         = true
  owner         = true
}

resource "aws_s3_bucket_cors_configuration" "cluster_b" {
  provider = aws.cluster_b
  for_each = local.cors_cluster_b_buckets
  bucket   = garage_bucket.cluster_b[each.key].global_alias

  cors_rule {
    allowed_headers = each.value.cors.allowed_headers
    allowed_methods = each.value.cors.allowed_methods
    allowed_origins = each.value.cors.allowed_origins
    expose_headers  = each.value.cors.expose_headers
    max_age_seconds = each.value.cors.max_age_seconds
  }
}

resource "aws_s3_bucket_website_configuration" "cluster_b" {
  provider = aws.cluster_b
  for_each = local.website_cluster_b_buckets
  bucket   = garage_bucket.cluster_b[each.key].global_alias

  index_document {
    suffix = each.value.website.index_document
  }

  error_document {
    key = each.value.website.error_document
  }
}

# ==============================================================================
# 3. Offsite DR Storage: Backblaze B2
# Cloud replica bucket creation and optional prune policies
# ==============================================================================

resource "aws_s3_bucket" "backblaze" {
  provider = aws.backblaze
  for_each = local.backblaze_buckets
  bucket   = each.value.bucket_name
}

resource "aws_s3_bucket_lifecycle_configuration" "backblaze" {
  provider = aws.backblaze
  for_each = {
    for k, v in local.backblaze_buckets : k => v
    if v.backups.backblaze.prune.enabled
  }
  bucket = aws_s3_bucket.backblaze[each.key].id

  rule {
    id     = "prune-old-backups"
    status = "Enabled"

    filter {}

    expiration {
      days = tonumber(replace(each.value.backups.backblaze.prune.age_to_prune, "d", ""))
    }
  }
}

# ==============================================================================
# 4. OpenBao (Vault KV) Secrets Management
# Sync credentials directly to /garage/home-infra/<bucket>
# ==============================================================================

resource "vault_kv_secret_v2" "synology_credentials" {
  for_each = local.synology_buckets
  mount    = "secret"
  name     = "garage/home-infra/${each.value.bucket_name}"

  data_json = jsonencode({
    ACCESS_KEY_ID     = garage_key.synology[each.key].access_key_id
    ACCESS_SECRET_KEY = garage_key.synology[each.key].secret_access_key
    ACCESS_REGION     = "garage"
  })
}

resource "vault_kv_secret_v2" "cluster_b_credentials" {
  for_each = local.cluster_b_buckets
  mount    = "secret"
  name     = "garage/home-infra/${each.value.bucket_name}"

  data_json = jsonencode({
    ACCESS_KEY_ID     = garage_key.cluster_b[each.key].access_key_id
    ACCESS_SECRET_KEY = garage_key.cluster_b[each.key].secret_access_key
    ACCESS_REGION     = "garage"
  })
}

# When Backblaze is enabled, ensure /backblaze/home-infra/<bucket> is stored
resource "vault_kv_secret_v2" "backblaze_credentials" {
  for_each = {
    for k, v in local.backblaze_buckets : k => v
    if var.backblaze_access_key_id != ""
  }
  mount = "secret"
  name  = "backblaze/home-infra/${each.value.bucket_name}"

  data_json = jsonencode({
    AWS_ACCESS_KEY_ID     = var.backblaze_access_key_id
    AWS_SECRET_ACCESS_KEY = var.backblaze_secret_access_key
    AWS_REGION            = var.backblaze_region
  })
}
