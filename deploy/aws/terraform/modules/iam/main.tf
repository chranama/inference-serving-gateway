locals {
  github_actions_enabled = length(var.github_oidc_repositories) > 0
  github_subjects = [
    for repository in var.github_oidc_repositories :
    "repo:${repository}:ref:refs/heads/${var.github_actions_branch}"
  ]
}

data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${var.name_prefix}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-eks-cluster"
    },
  )
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  for_each = toset(
    [
      "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
      "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController",
    ],
  )

  role       = aws_iam_role.eks_cluster.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "${var.name_prefix}-eks-node"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-eks-node"
    },
  )
}

resource "aws_iam_role_policy_attachment" "eks_node" {
  for_each = toset(
    [
      "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
      "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
      "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly",
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
      "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    ],
  )

  role       = aws_iam_role.eks_node.name
  policy_arn = each.value
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = local.github_actions_enabled ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.github_oidc_thumbprints

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-github-oidc"
    },
  )
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  count = local.github_actions_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_subjects
    }
  }
}

resource "aws_iam_role" "github_actions_image_publish" {
  count = local.github_actions_enabled ? 1 : 0

  name               = "${var.name_prefix}-gha-publish"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role[0].json

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-gha-publish"
    },
  )
}

data "aws_iam_policy_document" "github_actions_ecr_publish" {
  count = local.github_actions_enabled ? 1 : 0

  statement {
    sid = "EcrAuthorization"

    actions = [
      "ecr:GetAuthorizationToken",
    ]

    resources = ["*"]
  }

  statement {
    sid = "RepositoryPushPull"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]

    resources = [
      var.gateway_repository_arn,
      var.backend_repository_arn,
    ]
  }
}

resource "aws_iam_policy" "github_actions_ecr_publish" {
  count = local.github_actions_enabled ? 1 : 0

  name   = "${var.name_prefix}-gha-ecr-publish"
  policy = data.aws_iam_policy_document.github_actions_ecr_publish[0].json

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-gha-ecr-publish"
    },
  )
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr_publish" {
  count = local.github_actions_enabled ? 1 : 0

  role       = aws_iam_role.github_actions_image_publish[0].name
  policy_arn = aws_iam_policy.github_actions_ecr_publish[0].arn
}
