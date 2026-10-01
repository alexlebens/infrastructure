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

import {
  to = garage_bucket.a_ps02sn["volsync"]
  id = "c73ae1750f8a5d2548011700a30bd5c281997a24c7d6c64dfe8efdd848081299"
}

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

import {
  to = garage_bucket.c_ps10rp["volsync"]
  id = "963a8d928b04d0c91f8a787849d71755eababf661f1742a0ab2e6fd7f0c99ac2"
}

# ------------------------------------------------------------------------------
# Offsite DR Storage: Tier D - Backblaze B2 (d_cs01bb)
# Only apps with `s3-bucket: enabled: true` are declared in Tofu.
# ------------------------------------------------------------------------------
import {
  to = b2_bucket.d_cs01bb["affine"]
  id = "5d710b5eea3ce5a2ad0f0211" # affine-assets-6dd4468fad57973f
}

import {
  to = b2_bucket.d_cs01bb["reactive-resume"]
  id = "cd419b0eba4c2562ad0f0211" # reactive-resume-assets-61758b59b4c7c893
}

import {
  to = b2_bucket.d_cs01bb["web-assets"]
  id = "cd910b4e5a9cf5529ddf0211" # web-assets-770aef58c931fcf4
}

import {
  to = b2_bucket.d_cs01bb["volsync"]
  id = "cdd1eb7e3a7cf5529ddf0211" # volsync-backups-c1c03d37545d9c27
}

# ------------------------------------------------------------------------------
# Future Migrations:
# Uncomment these import blocks as each app is migrated from `garage-bucket` to `s3-bucket`:
# ------------------------------------------------------------------------------
# import { to = b2_bucket.d_cs01bb["backrest"]  id = "6d111bce3a8cf5529ddf0211" } # backrest-def20def9a764fc3
# import { to = b2_bucket.d_cs01bb["gitea"]     id = "3db1ebbe5a2c25c2ad0f0211" } # gitea-assets-6670d003410bb125
# import { to = b2_bucket.d_cs01bb["kaneo"]     id = "2da12b0eda7ce5c29def0211" } # kaneo-asssets-47edc3f232f2797f
# import { to = b2_bucket.d_cs01bb["karakeep"]  id = "2dd16bbe3abcf5529ddf0211" } # karakeep-assets-bcb0bc04dac3e3fd
# import { to = b2_bucket.d_cs01bb["mariadb"]   id = "2db19b2e3a8cf5529ddf0211" } # mariadb-backups-6e3b78870f7af040
# import { to = b2_bucket.d_cs01bb["openbao"]   id = "0d81cbee3a8cf5529ddf0211" } # openbao-backups-038053cd180284dc
# import { to = b2_bucket.d_cs01bb["outline"]   id = "1db16b6eea4cf5d29dff0211" } # outline-assets-2ac99fb083071f74
# import { to = b2_bucket.d_cs01bb["pocket-id"] id = "6de1eb0e1a2cd5d29dff0211" } # pocket-id-assets-708b709d424a4664
# import { to = b2_bucket.d_cs01bb["postgres"]  id = "1d312bce3a2cf5529ddf0211" } # postgres-backups-775957147abfbc73
# import { to = b2_bucket.d_cs01bb["talos"]     id = "cd111b9e3a9cf5529ddf0211" } # talos-backups-8c38c0f91be53b11
