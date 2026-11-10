variable "harbor_url" {
  description = "Harbor external URL"
  type        = string
  default     = "https://harbor.alexlebens.dev"
}

variable "harbor_username" {
  description = "Harbor username used by the provider (robot accounts look like robot$tofu). Set via TF_VAR_harbor_username"
  type        = string
  default     = "admin"
}

variable "harbor_password" {
  description = "Harbor password/robot secret (OpenBao: cl01tl/harbor/tofu, property password). Set via TF_VAR_harbor_password"
  type        = string
  sensitive   = true
  default     = ""
}
