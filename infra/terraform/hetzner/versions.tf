terraform {
  required_version = ">= 1.6.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.70"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # Configure a remote backend for real use, e.g. an S3-compatible bucket:
  # backend "s3" {}
}

provider "hcloud" {
  token = var.hcloud_token
}
