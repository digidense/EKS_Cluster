########################################################
# VARIABLES
########################################################

variable "cluster_name" {
  description = "EKS Cluster name"
  type        = string
  default     = "my-eks-cluster"
}

variable "node_group_name" {
  description = "EKS Node group name"
  type        = string
  default     = "my-node-group"
}

# Optional manual subnet override (defaults to [])
variable "subnet_ids" {
  description = "Subnets for EKS"
  type        = list(string)
  default     = []
}

# Optional manual security group override (defaults to [])
variable "security_group_ids" {
  description = "Security groups for EKS"
  type        = list(string)
  default     = []
}

variable "desired_size" {
  description = "Desired node count"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Max node count"
  type        = number
  default     = 3
}

variable "min_size" {
  description = "Min node count"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

########################################################
# EC2 INSTANCE VARIABLES
########################################################

variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.small"
}

variable "ec2_instance_name" {
  description = "Name for the EC2 instance"
  type        = string
  default     = "minimal-instance"
}
