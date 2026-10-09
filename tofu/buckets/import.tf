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
