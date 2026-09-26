provider "garage" {
  alias  = "synology_a"
  host   = var.garage_synology_a_host
  scheme = var.garage_synology_a_scheme
  token  = var.garage_synology_a_token
}

provider "garage" {
  alias  = "cluster_b"
  host   = var.garage_cluster_b_host
  scheme = var.garage_cluster_b_scheme
  token  = var.garage_cluster_b_token
}

provider "vault" {
  address = var.openbao_address
  token   = var.openbao_token
}

provider "aws" {
  alias                       = "synology_a"
  region                      = "garage"
  endpoints {
    s3 = var.garage_synology_a_s3_endpoint
  }
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  s3_use_path_style           = true
  access_key                  = var.garage_synology_a_admin_access_key
  secret_key                  = var.garage_synology_a_admin_secret_key
}

provider "aws" {
  alias                       = "cluster_b"
  region                      = "garage"
  endpoints {
    s3 = var.garage_cluster_b_s3_endpoint
  }
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  s3_use_path_style           = true
  access_key                  = var.garage_cluster_b_admin_access_key
  secret_key                  = var.garage_cluster_b_admin_secret_key
}

provider "aws" {
  alias                       = "backblaze"
  region                      = var.backblaze_region
  endpoints {
    s3 = "https://s3.${var.backblaze_region}.backblazeb2.com"
  }
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  s3_use_path_style           = true
  access_key                  = var.backblaze_access_key_id
  secret_key                  = var.backblaze_secret_access_key
}
