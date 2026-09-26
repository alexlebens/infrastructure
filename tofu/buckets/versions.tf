terraform {
  required_version = ">= 1.8.0"

  backend "http" {
    address  = "https://gitea.alexlebens.dev/api/packages/alexlebens/terraform/state/s3-buckets"
    username = "alexlebens"
  }

  required_providers {
    garage = {
      source  = "registry.terraform.io/arsolitt/garagehq"
      version = "~> 1.2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    b2 = {
      source  = "Backblaze/b2"
      version = "~> 0.8"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
