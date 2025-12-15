# EKS Cluster - Terraform Infrastructure

## Overview
This is a Terraform/OpenTofu infrastructure-as-code project for provisioning AWS EKS (Elastic Kubernetes Service) clusters. It contains two cluster configurations:

1. **eks-cluster-01**: Basic EKS cluster with managed node groups
2. **eks-cluster-karpenter**: Advanced EKS cluster with Karpenter autoscaler and NGINX Ingress Controller

## Project Structure
```
├── eks-cluster-01/          # Basic EKS cluster configuration
│   ├── main.tf              # Main infrastructure definitions
│   ├── variables.tf         # Input variables
│   ├── output.tf            # Output values
│   └── provider.tf          # AWS provider configuration
│
├── eks-cluster-karpenter/   # EKS with Karpenter autoscaling
│   ├── main.tf              # EKS + Karpenter + NGINX Ingress
│   ├── variables.tf         # Input variables
│   ├── output.tf            # Output values
│   ├── provider.tf          # AWS/Helm providers
│   ├── karpenter-provisioner.yaml
│   ├── deployment.yaml
│   ├── ingress.yaml
│   ├── inflate.yaml
│   └── kube-bench/          # Kubernetes security benchmark
│
└── README.md
```

## Requirements
- **OpenTofu** (Terraform-compatible): Installed via Replit
- **AWS Credentials**: Required for actual deployments (set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY)

## Usage

### Validate Configuration
```bash
cd eks-cluster-01
tofu validate

cd eks-cluster-karpenter
tofu validate
```

### Plan Infrastructure Changes
```bash
cd eks-cluster-01
tofu plan
```

### Apply Infrastructure (requires AWS credentials)
```bash
cd eks-cluster-01
tofu apply
```

## Notes
- This is an infrastructure project, not a web application
- Actual AWS deployment requires AWS credentials configured
- State files (*.tfstate) are in .gitignore for security
