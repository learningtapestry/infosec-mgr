# IAM resources for EC2 instance

# IAM role for EC2 instance
resource "aws_iam_role" "defectdojo" {
  name = "defectdojo-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "defectdojo-ec2-role"
  }
}

# IAM policy for S3 backup access
resource "aws_iam_role_policy" "s3_backup" {
  name = "defectdojo-s3-backup"
  role = aws_iam_role.defectdojo.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BackupAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.backups.arn,
          "${aws_s3_bucket.backups.arn}/*"
        ]
      }
    ]
  })
}

# Instance profile
resource "aws_iam_instance_profile" "defectdojo" {
  name = "defectdojo-instance-profile"
  role = aws_iam_role.defectdojo.name
}
