# ==============================================================================
# Explicit OpenTofu Resource Imports
#
# INSTRUCTIONS:
# 1. Fill in any missing Bucket IDs (see docs or queries below).
# 2. Run `tofu plan` to preview the import.
# 3. Run `tofu apply` to import them into your Gitea remote state.
# 4. Once `tofu apply` succeeds and the resources exist in state, DELETE these
#    import blocks from this file.
# ==============================================================================

# ------------------------------------------------------------------------------
# Primary S3 Storage: Tier A - Synology NAS (a_ps02sn)
# ------------------------------------------------------------------------------
import {
  to = garage_bucket.a_ps02sn["web-assets"]
  id = "6a509026035a0797211b6fc07cbcf51404953ae9278fb9a414a55aceb0abf670"
}

# import {
#   to = garage_bucket.a_ps02sn["affine"]
#   id = "<SYNOLOGY_A_AFFINE_ASSETS_HEX_BUCKET_ID>"
# }

# ------------------------------------------------------------------------------
# Primary S3 Storage: Tier B - Talos K8s Cluster (b_cl01tl)
# ------------------------------------------------------------------------------
import {
  to = garage_bucket.b_cl01tl["reactive-resume"]
  id = "23cdcf4b0797078fe2addeb430250f4ec1853a25ac6810327979f00890553d46"
}

# import {
#   to = garage_bucket.b_cl01tl["web-assets"]
#   id = "<CLUSTER_B_WEB_ASSETS_HEX_BUCKET_ID>"
# }

# import {
#   to = garage_bucket.b_cl01tl["affine"]
#   id = "<CLUSTER_B_AFFINE_ASSETS_HEX_BUCKET_ID>"
# }

# ------------------------------------------------------------------------------
# Secondary S3 Storage: Tier C - Raspberry Pi (c_ps10rp)
# ------------------------------------------------------------------------------
# import {
#   to = garage_bucket.c_ps10rp["web-assets"]
#   id = "<RASPBERRY_PI_C_WEB_ASSETS_HEX_BUCKET_ID>"
# }

# import {
#   to = garage_bucket.c_ps10rp["affine"]
#   id = "<RASPBERRY_PI_C_AFFINE_ASSETS_HEX_BUCKET_ID>"
# }

# ------------------------------------------------------------------------------
# Offsite DR Storage: Tier D - Backblaze B2 (d_cs01bb)
# Note: Backblaze B2 bucket import requires the B2 Bucket ID (found in B2 Console / CLI)
# ------------------------------------------------------------------------------
# import {
#   to = b2_bucket.d_cs01bb["web-assets"]
#   id = "<B2_WEB_ASSETS_BUCKET_ID>" # target bucket: web-assets-770aef58c931fcf4
# }

# import {
#   to = b2_bucket.d_cs01bb["reactive-resume"]
#   id = "<B2_REACTIVE_RESUME_BUCKET_ID>" # target bucket: reactive-resume-assets-61758b59b4c7c893
# }

# import {
#   to = b2_bucket.d_cs01bb["affine"]
#   id = "<B2_AFFINE_ASSETS_BUCKET_ID>" # target bucket: affine-assets-6dd4468fad57973f
# }
