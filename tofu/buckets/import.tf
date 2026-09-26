# ==============================================================================
# Non-Destructive Adoption of Pre-Existing Buckets & Keys
# Prevents recreating buckets that already contain live production data.
# ==============================================================================

# --- web-assets (Synology A Pilot) ---
import {
  to = garage_bucket.synology["web-assets"]
  id = "eb1fab00d33a8a4b"
}

import {
  to = garage_key.synology["web-assets"]
  id = "GK2c0630ba0e4e1ddc6a333133"
}

import {
  to = garage_bucket_key.synology["web-assets"]
  id = "eb1fab00d33a8a4b/GK2c0630ba0e4e1ddc6a333133"
}

# --- reactive-resume-assets (Cluster B Pilot) ---
import {
  to = garage_bucket.cluster_b["reactive-resume"]
  id = "23cdcf4b0797078fe2addeb430250f4ec1853a25ac6810327979f00890553d46"
}

import {
  to = garage_key.cluster_b["reactive-resume"]
  id = "GK7f9683d79c477fb872cafb00"
}

import {
  to = garage_bucket_key.cluster_b["reactive-resume"]
  id = "23cdcf4b0797078fe2addeb430250f4ec1853a25ac6810327979f00890553d46/GK7f9683d79c477fb872cafb00"
}
