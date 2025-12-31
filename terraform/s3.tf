# S3 bucket for DefectDojo backups

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "backups" {
  bucket = "infosec-mgr-backups-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "infosec-mgr-backups"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Enable versioning for backup safety
resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle rules for tiered backup retention
# - Daily backups: 30 days
# - Monthly backups: 180 days (6 months)
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    expiration {
      expired_object_delete_marker = true
    }
  }

  rule {
    id     = "daily-backup-retention"
    status = "Enabled"

    filter {
      prefix = "backups/daily/"
    }

    expiration {
      days = 30
    }
  }

  rule {
    id     = "monthly-backup-retention"
    status = "Enabled"

    filter {
      prefix = "backups/monthly/"
    }

    expiration {
      days = 180
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
