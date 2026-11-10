terraform {
  required_version = ">= 1.8.0"

  backend "http" {
    address  = "https://gitea.alexlebens.dev/api/packages/alexlebens/terraform/state/harbor"
    username = "alexlebens"
  }

  required_providers {
    harbor = {
      source  = "goharbor/harbor"
      version = "3.12.5"
    }
  }
}
