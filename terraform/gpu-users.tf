# IAM users for vector-traversal GPU experiments

# --- Scoped GPU user (EC2 + S3 only) ---

resource "aws_iam_user" "gpu_scoped" {
  name = "vector-traversal-gpu"
  tags = { Purpose = "GPU experiment instances for vector-traversal research" }
}

resource "aws_iam_access_key" "gpu_scoped" {
  user = aws_iam_user.gpu_scoped.name
}

resource "aws_iam_user_policy" "gpu_scoped" {
  name = "gpu-experiment-policy"
  user = aws_iam_user.gpu_scoped.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2ForGPU"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances", "ec2:TerminateInstances",
          "ec2:DescribeInstances", "ec2:DescribeInstanceTypes",
          "ec2:DescribeImages", "ec2:DescribeKeyPairs",
          "ec2:DescribeSecurityGroups", "ec2:DescribeSubnets",
          "ec2:DescribeVpcs", "ec2:CreateKeyPair", "ec2:DeleteKeyPair",
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateTags", "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstanceStatus"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3ForResults"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:ListBucket", "s3:DeleteObject"]
        Resource = ["arn:aws:s3:::vector-traversal-*", "arn:aws:s3:::vector-traversal-*/*"]
      },
      {
        Sid    = "S3CreateBucket"
        Effect = "Allow"
        Action = ["s3:CreateBucket", "s3:PutBucketPolicy", "s3:PutBucketTagging"]
        Resource = "arn:aws:s3:::vector-traversal-*"
      },
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = "*"
        Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
      }
    ]
  })
}

# --- Admin user (full access backup) ---

resource "aws_iam_user" "gpu_admin" {
  name = "vector-traversal-admin"
  tags = { Purpose = "Admin backup for infosec AWS account" }
}

resource "aws_iam_access_key" "gpu_admin" {
  user = aws_iam_user.gpu_admin.name
}

resource "aws_iam_user_policy_attachment" "gpu_admin" {
  user       = aws_iam_user.gpu_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# --- Outputs ---

output "gpu_scoped_access_key_id" {
  value     = aws_iam_access_key.gpu_scoped.id
  sensitive = true
}

output "gpu_scoped_secret_key" {
  value     = aws_iam_access_key.gpu_scoped.secret
  sensitive = true
}

output "gpu_admin_access_key_id" {
  value     = aws_iam_access_key.gpu_admin.id
  sensitive = true
}

output "gpu_admin_secret_key" {
  value     = aws_iam_access_key.gpu_admin.secret
  sensitive = true
}
