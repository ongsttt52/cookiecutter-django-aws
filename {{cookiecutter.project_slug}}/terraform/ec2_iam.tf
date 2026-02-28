{% if cookiecutter.aws_deployment == "ec2-all-in-one" %}
# ==============================================================================
# EC2 IAM Role + Instance Profile
# ==============================================================================

# EC2 IAM Role
resource "aws_iam_role" "ec2_role" {
  name = "${local.project_name_normalized}-ec2-role-${var.environment}"

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
    Name = "${local.project_name_normalized}-ec2-role-${var.environment}"
  }
}

# S3 Access Policy
resource "aws_iam_role_policy" "ec2_s3_policy" {
  name = "${local.project_name_normalized}-ec2-s3-policy-${var.environment}"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.media.arn,
          "${aws_s3_bucket.media.arn}/*"
        ]
      }
    ]
  })
}

# CloudWatch Logs Policy
resource "aws_iam_role_policy" "ec2_cloudwatch_policy" {
  name = "${local.project_name_normalized}-ec2-cw-policy-${var.environment}"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.ec2.arn}:*"
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "ec2" {
  name = "${local.project_name_normalized}-ec2-profile-${var.environment}"
  role = aws_iam_role.ec2_role.name

  tags = {
    Name = "${local.project_name_normalized}-ec2-profile-${var.environment}"
  }
}
{% endif %}
