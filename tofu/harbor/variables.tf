variable "harbor_url" {
  description = "Harbor external URL"
  type        = string
  default     = "https://harbor.alexlebens.dev"
}

variable "harbor_username" {
  description = "Harbor admin username used by the provider"
  type        = string
  default     = "admin"
}

variable "harbor_password" {
  description = "Harbor admin password (OpenBao: /cl01tl/harbor/config, property admin-password). Set via TF_VAR_harbor_password"
  type        = string
  sensitive   = true
  default     = ""
}
