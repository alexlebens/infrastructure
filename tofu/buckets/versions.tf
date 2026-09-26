terraform {
  required_version = ">= 1.8.0"

  backend "http" {
    address        = "https://gitea.alexlebens.dev/api/packages/alexlebens/terraform/state/s3-buckets"
    lock_address   = "https://gitea.alexlebens.dev/api/packages/alexlebens/terraform/state/s3-buckets/lock"
    unlock_address = "https://gitea.alexlebens.dev/api/packages/alexlebens/terraform/state/s3-buckets/lock"
    username       = "alexlebens"
  }

  required_providers {
    garage = {
      source  = "arsolitt/garagehq"
      version = "~> 1.2.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
