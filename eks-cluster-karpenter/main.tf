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
    "arn:aws:iam::aws:policy/AmazonEKSServicePolicy",
    "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy",
    "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
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

########################################################
# KARPENTER IAM ROLES
########################################################

# Role for Karpenter Controller
resource "aws_iam_role" "karpenter_controller_role" {
  name_prefix = "karpenter-controller-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ])
  role       = aws_iam_role.karpenter_controller_role.name
  policy_arn = each.value
}

# Role for EC2 instances launched by Karpenter
resource "aws_iam_role" "karpenter_node_role" {
  name_prefix = "karpenter-node-role-"

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

resource "aws_iam_role_policy_attachment" "karpenter_node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ])
  role       = aws_iam_role.karpenter_node_role.name
  policy_arn = each.value
}

# Instance Profile for EC2 nodes
resource "aws_iam_instance_profile" "karpenter_node_profile" {
  name = "karpenter-node-instance-profile"
  role = aws_iam_role.karpenter_node_role.name
}

########################################################
# KARPENTER INSTALLATION (HELM)
########################################################

#resource "helm_release" "karpenter" {
#  name             = "karpenter"
#  repository       = "oci://public.ecr.aws/karpenter/karpenter"
#  chart            = "karpenter"
#  namespace        = "karpenter"
#  create_namespace = true
#  version          = "21.8.0"    # <-- update this to a valid version
#
#  depends_on = [aws_eks_cluster.main]
#
#  set {
#    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
#    value = aws_iam_role.karpenter_controller_role.arn
#  }
#
#  set {
#    name  = "settings.clusterName"
#    value = aws_eks_cluster.main.name
#  }
#
#  set {
#    name  = "settings.clusterEndpoint"
#    value = aws_eks_cluster.main.endpoint
#  }
#
#  set {
#    name  = "settings.interruptionQueueName"
#    value = "karpenter-interruption-queue"
#  }
#}

########################################################
# DATA SOURCES
########################################################
data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "main" {
  name = aws_eks_cluster.main.name
}

data "aws_eks_cluster_auth" "main" {
  name = aws_eks_cluster.main.name
}

########################################################
# HELM PROVIDER (Connect to EKS Cluster)
########################################################
provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

########################################################
# INSTALL KARPENTER VIA HELM
########################################################
resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = "karpenter"
  create_namespace = true

  repository = "https://charts.karpenter.sh/"
  chart      = "karpenter"
  version    = "0.16.3"  # ✅ Use stable version per docs

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter_controller_role.arn
  }

  set {
    name  = "clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "clusterEndpoint"
    value = aws_eks_cluster.main.endpoint
  }

  set {
    name  = "aws.defaultInstanceProfile"
    value = aws_iam_instance_profile.karpenter_node_profile.name
  }

  # optional but recommended to wait for webhook
  wait = true
}
