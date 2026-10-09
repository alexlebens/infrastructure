# ==============================================================================
# Gitea
# ==============================================================================

variable "gitea_token" {
  description = "Gitea token for state locking and HTTP backend authentication"
  type        = string
  sensitive   = true
  default     = ""
}

# ==============================================================================
# Tier A: (ps02sn)
# ==============================================================================

variable "garage_a_ps02sn_host" {
  description = "Host and port for Garage Admin API on Synology A (ps02sn)"
  type        = string
  default     = "synology.alexlebens.dev:3903"
}

variable "garage_a_ps02sn_scheme" {
  description = "Scheme for Garage Admin API on Synology A (http or https)"
  type        = string
  default     = "http"
}

variable "garage_a_ps02sn_token" {
  description = "Admin token for Garage on Synology A"
  type        = string
  sensitive   = true
  default     = ""
}

variable "garage_a_ps02sn_s3_endpoint" {
  description = "S3 API endpoint for Synology A"
  type        = string
  default     = "http://synology.alexlebens.dev:3900"
}

variable "garage_a_ps02sn_admin_access_key" {
  description = "S3 Admin Access Key for Synology A (for CORS/Website S3 calls)"
  type        = string
  default     = ""
}

variable "garage_a_ps02sn_admin_secret_key" {
  description = "S3 Admin Secret Key for Synology A (for CORS/Website S3 calls)"
  type        = string
  sensitive   = true
  default     = ""
}

# ==============================================================================
# Tier B: (cl01tl - garage-b)
# ==============================================================================

variable "garage_b_cl01tl_host" {
  description = "Host and port for Garage Admin API on Cluster B (cl01tl)"
  type        = string
  default     = "cluster-b.garage-b:3903"
}

variable "garage_b_cl01tl_scheme" {
  description = "Scheme for Garage Admin API on Cluster B (http or https)"
  type        = string
  default     = "http"
}

variable "garage_b_cl01tl_token" {
  description = "Admin token for Garage on Cluster B"
  type        = string
  sensitive   = true
  default     = ""
}

variable "garage_b_cl01tl_s3_endpoint" {
  description = "S3 API endpoint for Cluster B"
  type        = string
  default     = "http://cluster-b.garage-b:3900"
}

variable "garage_b_cl01tl_admin_access_key" {
  description = "S3 Admin Access Key for Cluster B (for CORS/Website S3 calls)"
  type        = string
  default     = ""
}

variable "garage_b_cl01tl_admin_secret_key" {
  description = "S3 Admin Secret Key for Cluster B (for CORS/Website S3 calls)"
  type        = string
  sensitive   = true
  default     = ""
}

# ==============================================================================
# Tier C: (ps10rp)
# ==============================================================================

variable "garage_c_ps10rp_host" {
  description = "Host and port for Garage Admin API on Raspberry Pi (ps10rp)"
  type        = string
  default     = "garage-ps10rp.boreal-beaufort.ts.net:3903"
}

variable "garage_c_ps10rp_scheme" {
  description = "Scheme for Garage Admin API on Raspberry Pi (http or https)"
  type        = string
  default     = "https"
}

variable "garage_c_ps10rp_token" {
  description = "Admin token for Garage on Raspberry Pi"
  type        = string
  sensitive   = true
  default     = ""
}

variable "garage_c_ps10rp_s3_endpoint" {
  description = "S3 API endpoint for Raspberry Pi"
  type        = string
  default     = "https://garage-ps10rp.boreal-beaufort.ts.net:3900"
}

variable "garage_c_ps10rp_admin_access_key" {
  description = "S3 Admin Access Key for Raspberry Pi"
  type        = string
  default     = ""
}

variable "garage_c_ps10rp_admin_secret_key" {
  description = "S3 Admin Secret Key for Raspberry Pi"
  type        = string
  sensitive   = true
  default     = ""
}

# ==============================================================================
# Tier D: (cs01bb)
# ==============================================================================

variable "backblaze_d_cs01bb_region" {
  description = "Backblaze B2 AWS region"
  type        = string
  default     = "us-east-005"
}

variable "backblaze_d_cs01bb_endpoint" {
  description = "Backblaze B2 S3 API endpoint"
  type        = string
  default     = "https://s3.us-east-005.backblazeb2.com"
}

variable "backblaze_d_cs01bb_access_key_id" {
  description = "Backblaze B2 Application Key ID"
  type        = string
  default     = ""
}

variable "backblaze_d_cs01bb_secret_access_key" {
  description = "Backblaze B2 Application Key"
  type        = string
  sensitive   = true
  default     = ""
}

# ==============================================================================
# OpenBao / Vault
# ==============================================================================

variable "openbao_address" {
  description = "OpenBao address"
  type        = string
  default     = "http://openbao-internal.openbao:8200"
}

variable "openbao_token" {
  description = "Token to authenticate with OpenBao"
  type        = string
  sensitive   = true
  default     = ""
}

# ==============================================================================
# VolSync Restic Passwords (per Storage Tier)
# ==============================================================================

variable "volsync_restic_password_a_ps02sn" {
  description = "Restic repository password for VolSync backups on Tier A (ps02sn)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "volsync_restic_password_b_cl01tl" {
  description = "Restic repository password for VolSync backups on Tier B (cl01tl - garage-b)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "volsync_restic_password_c_ps10rp" {
  description = "Restic repository password for VolSync backups on Tier C (ps10rp)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "volsync_restic_password_d_cs01bb" {
  description = "Restic repository password for VolSync backups on Tier D (cs01bb)"
  type        = string
  sensitive   = true
  default     = ""
}
