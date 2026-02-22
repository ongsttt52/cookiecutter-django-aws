# ==============================================================================
# VPC 및 네트워크 설정
# ==============================================================================

# VPC 생성
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.project_name_normalized}-vpc-${var.environment}"
  }
}

# 인터넷 게이트웨이 (외부 인터넷 연결)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.project_name_normalized}-igw-${var.environment}"
  }
}

# Public 서브넷 (ALB, ECS가 위치)
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.project_name_normalized}-public-${count.index + 1}-${var.environment}"
  }
}

# Private 서브넷 (RDS, Redis가 위치)
resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${local.project_name_normalized}-private-${count.index + 1}-${var.environment}"
  }
}

# Public 라우트 테이블 (인터넷 게이트웨이로 연결)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.project_name_normalized}-public-rt-${var.environment}"
  }
}

# Public 서브넷을 라우트 테이블에 연결
resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
