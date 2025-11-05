########################################################
# DATA SOURCES FOR DEFAULT VPC
########################################################

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get subnets in the default VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get details of each subnet (to check AZ)
data "aws_subnet" "all" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

# Get default security group
data "aws_security_group" "default" {
  filter {
    name   = "group-name"
    values = ["default"]
  }
  vpc_id = data.aws_vpc.default.id
}

########################################################
# LOCALS
########################################################
locals {
  # Supported AZs for EKS in us-east-1
  supported_azs = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]

  # Filter out subnets in unsupported zones (like us-east-1e)
  filtered_subnets = [
  for subnet_id, subnet in data.aws_subnet.all : subnet_id
  if contains(local.supported_azs, subnet.availability_zone)
  ]

  # Choose subnet list
  subnet_ids         = length(var.subnet_ids) > 0 ? var.subnet_ids : local.filtered_subnets
  security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : [data.aws_security_group.default.id]
}
########################################################
# IAM ROLES
########################################################

# EKS Cluster Role
resource "aws_iam_role" "eks_cluster_role" {
  name_prefix = "eks-cluster-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  ])
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = each.value
}

# Node Group Role
resource "aws_iam_role" "eks_node_role" {
  name_prefix = "eks-node-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "eks_node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  ])
  role       = aws_iam_role.eks_node_role.name
  policy_arn = each.value
}

########################################################
# EKS CLUSTER
########################################################
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids         = local.subnet_ids
    security_group_ids = local.security_group_ids
  }

  tags = merge(var.tags, { Name = var.cluster_name })
}

########################################################
# EKS NODE GROUP
########################################################
resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = local.subnet_ids

  scaling_config {
    desired_size = var.desired_size
    max_size     = var.max_size
    min_size     = var.min_size
  }

  tags = merge(var.tags, { Name = var.node_group_name })
}

########################################################
# EKS ADDONS (CoreDNS, kube-proxy, VPC CNI)
########################################################
# Fetch latest addon versions dynamically
data "aws_eks_addon_version" "latest" {
  for_each = toset(["vpc-cni", "kube-proxy", "coredns"])
  addon_name   = each.key
  kubernetes_version = aws_eks_cluster.main.version
}

resource "aws_eks_addon" "addons" {
  for_each      = data.aws_eks_addon_version.latest
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = each.key
  addon_version = each.value.version
}
