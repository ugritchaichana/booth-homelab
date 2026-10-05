# ==============================================================================
# OpenTofu Remote S3 State Backend (MinIO Storage Fabric)
# ==============================================================================

terraform {
  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "homelab/terraform.tfstate"
    endpoints                   = { s3 = "http://10.99.20.20:9000" }
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    force_path_style            = true
  }
}
