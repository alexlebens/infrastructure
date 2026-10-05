# ==============================================================================
# Explicit OpenTofu Resource Imports
#
# NOTE:
# The arsolitt/garagehq provider does not implement the OpenTofu/Terraform Import
# interface for garage_bucket. Only b2_bucket resources can be imported via
# declarative `import` blocks.
#
# INSTRUCTIONS:
# 1. Fill in any missing Bucket IDs for b2_bucket resources.
# 2. Run `tofu plan` to preview the import.
# 3. Run `tofu apply` to import them into your Gitea remote state.
# 4. Once `tofu apply` succeeds and the resources exist in state, DELETE these
#    import blocks from this file.
# ==============================================================================


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
# import { to = b2_bucket.d_cs01bb["talos"]     id = "cd111b9e3a9cf5529ddf0211" } # talos-backups-8c38c0f91be53b11
