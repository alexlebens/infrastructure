# ==============================================================================
# Pre-Existing Buckets Note:
# The arsolitt/garagehq provider does not implement the Terraform Import API
# for garage_bucket or garage_key. Pre-existing buckets and keys are managed
# declaratively by matching their global aliases and key names.
# ==============================================================================

# ==============================================================================
# Pre-Existing Backblaze B2 Buckets
# Pre-existing cloud replica buckets are imported into state to avoid recreation.
# ==============================================================================

import {
  to = aws_s3_bucket.backblaze["web-assets"]
  id = "web-assets-770aef58c931fcf4"
}

import {
  to = aws_s3_bucket.backblaze["reactive-resume"]
  id = "reactive-resume-assets-61758b59b4c7c893"
}
