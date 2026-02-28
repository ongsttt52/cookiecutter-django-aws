{% if cookiecutter.aws_deployment == "ec2-all-in-one" %}
# ==============================================================================
# EC2 All-in-One (Docker Compose on single instance)
# ==============================================================================

# Amazon Linux 2023 AMI (x86_64)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# SSH Key Pair
resource "aws_key_pair" "ec2" {
  key_name   = "${local.project_name_normalized}-ec2-key-${var.environment}"
  public_key = var.ec2_public_key

  tags = {
    Name = "${local.project_name_normalized}-ec2-key-${var.environment}"
  }
}

# EC2 Instance
resource "aws_instance" "main" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = local.ec2_instance_type
  key_name               = aws_key_pair.ec2.key_name
  vpc_security_group_ids = [aws_security_group.ec2.id]
  subnet_id              = aws_subnet.public[0].id
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    project_slug          = var.project_name
    project_name_normalized = local.project_name_normalized
    db_password           = var.db_password
    django_secret_key     = var.django_secret_key
    s3_bucket_name        = aws_s3_bucket.media.bucket
    aws_region            = var.aws_region
    environment           = var.environment
  }))

  tags = {
    Name = "${local.project_name_normalized}-ec2-${var.environment}"
  }

  lifecycle {
    ignore_changes = [user_data, ami]
  }
}

# Elastic IP (fixed public IP)
resource "aws_eip" "ec2" {
  instance = aws_instance.main.id
  domain   = "vpc"

  tags = {
    Name = "${local.project_name_normalized}-eip-${var.environment}"
  }
}

# CloudWatch Log Group for EC2
resource "aws_cloudwatch_log_group" "ec2" {
  name              = "/ec2/${local.project_name_normalized}-${var.environment}"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name = "${local.project_name_normalized}-ec2-logs-${var.environment}"
  }
}
{% endif %}
