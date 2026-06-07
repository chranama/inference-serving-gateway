resource "aws_ecr_repository" "gateway" {
  name                 = var.gateway_repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    var.tags,
    {
      Name = var.gateway_repository_name
    },
  )
}

resource "aws_ecr_repository" "backend" {
  name                 = var.backend_repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    var.tags,
    {
      Name = var.backend_repository_name
    },
  )
}

resource "aws_ecr_lifecycle_policy" "gateway" {
  repository = aws_ecr_repository.gateway.name

  policy = jsonencode(
    {
      rules = [
        {
          rulePriority = 1
          description  = "Expire untagged gateway images beyond ten revisions"
          selection = {
            tagStatus   = "untagged"
            countType   = "imageCountMoreThan"
            countNumber = 10
          }
          action = {
            type = "expire"
          }
        },
        {
          rulePriority = 2
          description  = "Retain only the most recent bounded gateway image set"
          selection = {
            tagStatus   = "any"
            countType   = "imageCountMoreThan"
            countNumber = var.image_retention_count
          }
          action = {
            type = "expire"
          }
        },
      ]
    },
  )
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode(
    {
      rules = [
        {
          rulePriority = 1
          description  = "Expire untagged backend images beyond ten revisions"
          selection = {
            tagStatus   = "untagged"
            countType   = "imageCountMoreThan"
            countNumber = 10
          }
          action = {
            type = "expire"
          }
        },
        {
          rulePriority = 2
          description  = "Retain only the most recent bounded backend image set"
          selection = {
            tagStatus   = "any"
            countType   = "imageCountMoreThan"
            countNumber = var.image_retention_count
          }
          action = {
            type = "expire"
          }
        },
      ]
    },
  )
}
