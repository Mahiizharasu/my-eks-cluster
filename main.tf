provider "aws" {
 region = var.region
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "mahi-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
        Effect = "Allow"
        Principal = {
          Service = ["eks.amazonaws.com"]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "eks_cluster_policy_attach" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


resource "aws_eks_cluster" "eks_cluster" {
  name     = "mahi-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = var.subnets_id
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy_attach]
}


resource "aws_iam_role" "node_group_role" {
  name = "mahi-nodeGroupRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        Service = ["ec2.amazonaws.com"]
      }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_policy_attach" {
  count      = 3
  role       = aws_iam_role.node_group_role.name
  policy_arn = element(["arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
                        "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
                        "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"], count.index)
}

resource "aws_eks_node_group" "node_grp" {
  subnet_ids = var.subnets_id
  scaling_config {
    max_size = 3
    min_size = 2
    desired_size = 3
  }
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "mahi-node-grp"
  node_role_arn   = aws_iam_role.node_group_role.arn
}


provider "kubernetes" {
  host                   = aws_eks_cluster.eks_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks_cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks_auth.token
}

resource "kubernetes_cluster_role" "automation_role" {
  metadata {
    name = "mahi-cluster-automation-role"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}


resource "kubernetes_cluster_role_binding" "automation_role_binding" {
  metadata {
    name = "mahi-cluster-automation-binding"
  }

  subject {
    kind = "User"
    name = "automation-usr"  
  }

  role_ref {
    kind     = "ClusterRole"
    name     = kubernetes_cluster_role.automation_role.metadata[0].name
    api_group = "rbac.authorization.k8s.io"
  }
}

# Define the ClusterRole for admin user
resource "kubernetes_cluster_role" "admin_role" {
  metadata {
    name = "mahi-cluster-admin-role"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

# Define the ClusterRoleBinding for admin user
resource "kubernetes_cluster_role_binding" "admin_role_binding" {
  metadata {
    name = "mahi-cluster-admin-binding"
  }

  subject {
    kind = "User"
    name = "admin"  
  }

  role_ref {
    kind     = "ClusterRole"
    name     = kubernetes_cluster_role.admin_role.metadata[0].name
    api_group = "rbac.authorization.k8s.io"
  }
}

# Data block to get EKS authentication
data "aws_eks_cluster_auth" "eks_auth" {
  name = aws_eks_cluster.eks_cluster.name
}

# Define the aws-auth ConfigMap, making sure the roles are created first
resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

 

  depends_on = [
    kubernetes_cluster_role.admin_role,
    kubernetes_cluster_role.automation_role,
    kubernetes_cluster_role_binding.admin_role_binding,
    kubernetes_cluster_role_binding.automation_role_binding
  ]
}
