# ==============================================================================
# Garage HQ Providers
# ==============================================================================

# Tier A: Synology NAS (ps02sn)
provider "garage" {
  alias  = "a_ps02sn"
  host   = var.garage_a_ps02sn_host
  scheme = var.garage_a_ps02sn_scheme
  token  = var.garage_a_ps02sn_token
}

# Tier B: Talos Kubernetes Cluster (cl01tl)
provider "garage" {
  alias  = "b_cl01tl"
  host   = var.garage_b_cl01tl_host
  scheme = var.garage_b_cl01tl_scheme
  token  = var.garage_b_cl01tl_token
}

# Tier C: Raspberry Pi storage node (ps10rp)
provider "garage" {
  alias  = "c_ps10rp"
  host   = var.garage_c_ps10rp_host
  scheme = var.garage_c_ps10rp_scheme
  token  = var.garage_c_ps10rp_token
}

# ==============================================================================
# OpenBao / Vault Provider
# ==============================================================================
provider "vault" {
  address = var.openbao_address
  token   = var.openbao_token
}

# ==============================================================================
# AWS S3 API Providers (for CORS, Website, and Backblaze B2)
# ==============================================================================

# Tier A: Synology S3 API
provider "aws" {
  alias                       = "a_ps02sn"
  region                      = "garage"
  endpoints {
    s3 = var.garage_a_ps02sn_s3_endpoint
  }
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  s3_use_path_style           = true
  access_key                  = var.garage_a_ps02sn_admin_access_key != "" ? var.garage_a_ps02sn_admin_access_key : "mock_access_key"
  secret_key                  = var.garage_a_ps02sn_admin_secret_key != "" ? var.garage_a_ps02sn_admin_secret_key : "mock_secret_key"
}

# Tier B: Cluster B S3 API
provider "aws" {
  alias                       = "b_cl01tl"
  region                      = "garage"
  endpoints {
    s3 = var.garage_b_cl01tl_s3_endpoint
  }
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  s3_use_path_style           = true
  access_key                  = var.garage_b_cl01tl_admin_access_key != "" ? var.garage_b_cl01tl_admin_access_key : "mock_access_key"
  secret_key                  = var.garage_b_cl01tl_admin_secret_key != "" ? var.garage_b_cl01tl_admin_secret_key : "mock_secret_key"
}

# Tier C: Raspberry Pi S3 API
provider "aws" {
  alias                       = "c_ps10rp"
  region                      = "garage"
  endpoints {
    s3 = var.garage_c_ps10rp_s3_endpoint
  }
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  s3_use_path_style           = true
  access_key                  = var.garage_c_ps10rp_admin_access_key != "" ? var.garage_c_ps10rp_admin_access_key : "mock_access_key"
  secret_key                  = var.garage_c_ps10rp_admin_secret_key != "" ? var.garage_c_ps10rp_admin_secret_key : "mock_secret_key"
}

# Tier D: Cloud DR Storage (Backblaze B2 cs01bb)
provider "aws" {
  alias                       = "d_cs01bb"
  region                      = var.backblaze_d_cs01bb_region
  endpoints {
    s3 = "https://s3.${var.backblaze_d_cs01bb_region}.backblazeb2.com"
  }
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  s3_use_path_style           = true
  access_key                  = var.backblaze_d_cs01bb_access_key_id != "" ? var.backblaze_d_cs01bb_access_key_id : "mock_access_key"
  secret_key                  = var.backblaze_d_cs01bb_secret_access_key != "" ? var.backblaze_d_cs01bb_secret_access_key : "mock_secret_key"
}
