variable "gitea_token" {
  description = "Gitea token for state locking and HTTP backend authentication"
  type        = string
  sensitive   = true
  default     = ""
}

# --- Garage Synology A ---
variable "garage_synology_a_host" {
  description = "Host and port for Garage Admin API on Synology A"
  type        = string
  default     = "synology.alexlebens.dev:3903"
}

variable "garage_synology_a_scheme" {
  description = "Scheme for Garage Admin API on Synology A (http or https)"
  type        = string
  default     = "http"
}

variable "garage_synology_a_token" {
  description = "Admin token for Garage on Synology A"
  type        = string
  sensitive   = true
  default     = ""
}

variable "garage_synology_a_s3_endpoint" {
  description = "S3 API endpoint for Synology A"
  type        = string
  default     = "http://synology.alexlebens.dev:3900"
}

variable "garage_synology_a_admin_access_key" {
  description = "S3 Admin Access Key for Synology A (for CORS/Website S3 calls)"
  type        = string
  default     = ""
}

variable "garage_synology_a_admin_secret_key" {
  description = "S3 Admin Secret Key for Synology A (for CORS/Website S3 calls)"
  type        = string
  sensitive   = true
  default     = ""
}

# --- Garage Cluster B ---
variable "garage_cluster_b_host" {
  description = "Host and port for Garage Admin API on Cluster B"
  type        = string
  default     = "garage-cluster-b.garage-operator:3903"
}

variable "garage_cluster_b_scheme" {
  description = "Scheme for Garage Admin API on Cluster B (http or https)"
  type        = string
  default     = "http"
}

variable "garage_cluster_b_token" {
  description = "Admin token for Garage on Cluster B"
  type        = string
  sensitive   = true
  default     = ""
}

variable "garage_cluster_b_s3_endpoint" {
  description = "S3 API endpoint for Cluster B"
  type        = string
  default     = "http://garage-cluster-b.garage-operator:3900"
}

variable "garage_cluster_b_admin_access_key" {
  description = "S3 Admin Access Key for Cluster B (for CORS/Website S3 calls)"
  type        = string
  default     = ""
}

variable "garage_cluster_b_admin_secret_key" {
  description = "S3 Admin Secret Key for Cluster B (for CORS/Website S3 calls)"
  type        = string
  sensitive   = true
  default     = ""
}

# --- OpenBao / Vault ---
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

# --- Backblaze B2 ---
variable "backblaze_region" {
  description = "Backblaze B2 AWS region"
  type        = string
  default     = "us-east-005"
}

variable "backblaze_access_key_id" {
  description = "Backblaze B2 Application Key ID"
  type        = string
  default     = ""
}

variable "backblaze_secret_access_key" {
  description = "Backblaze B2 Application Key"
  type        = string
  sensitive   = true
  default     = ""
}
