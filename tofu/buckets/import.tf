# ==============================================================================
# Pre-Existing Buckets Note:
# The arsolitt/garagehq provider does not implement the Terraform Import API
# for garage_bucket or garage_key. Pre-existing buckets and keys are managed
# declaratively by matching their global aliases and key names.
# ==============================================================================

# ==============================================================================
# Pre-Existing Tier D (Backblaze B2 cs01bb) Buckets
# Pre-existing cloud replica buckets are imported into state by bucket ID.
# Configured / generated dynamically by .gitea/scripts/tofu-fetch-secrets.sh.
# ==============================================================================
