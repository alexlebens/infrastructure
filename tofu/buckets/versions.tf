terraform {
  required_version = ">= 1.8.0"

  backend "http" {
    address = "https://gitea.alexlebens.dev/api/packages/alexlebens/terraform/state/s3-buckets"
  }

  required_providers {
    garage = {
      source  = "registry.terraform.io/arsolitt/garagehq"
      version = "1.2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "6.66.0"
    }
    b2 = {
      source  = "Backblaze/b2"
      version = "0.14.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.12.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }
}
