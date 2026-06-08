resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.cluster_version

  enabled_cluster_log_types = var.enabled_cluster_log_types

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = var.endpoint_public_access
    endpoint_private_access = var.endpoint_private_access
  }

  tags = merge(
    var.tags,
    {
      Name = var.cluster_name
    },
  )
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-${var.node_group_name}"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.node_subnet_ids
  instance_types  = var.node_instance_types
  disk_size       = var.node_disk_size
  capacity_type   = var.node_capacity_type
  ami_type        = "AL2023_x86_64_STANDARD"

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${var.node_group_name}"
    },
  )
}

resource "aws_eks_node_group" "gpu" {
  count = var.enable_gpu_node_group ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-${var.gpu_node_group_name}"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.node_subnet_ids
  instance_types  = var.gpu_node_instance_types
  disk_size       = var.gpu_node_disk_size
  capacity_type   = var.gpu_node_capacity_type
  ami_type        = var.gpu_node_ami_type

  labels = {
    workload      = "model-runtime"
    accelerator   = "nvidia"
    runtime-slice = "aws-vllm"
  }

  taint {
    key    = "workload"
    value  = "model-runtime"
    effect = "NO_SCHEDULE"
  }

  scaling_config {
    desired_size = var.gpu_node_desired_size
    min_size     = var.gpu_node_min_size
    max_size     = var.gpu_node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(
    var.tags,
    {
      Name            = "${var.cluster_name}-${var.gpu_node_group_name}"
      workload        = "model-runtime"
      accelerator     = "nvidia"
      "runtime-slice" = "aws-vllm"
    },
  )
}
