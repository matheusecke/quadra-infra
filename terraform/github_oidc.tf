resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = merge(local.common_tags, {
    Name = "github-actions"
  })
}

data "aws_iam_policy_document" "api_deploy_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:matheusecke/quadra-api:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "api_deploy" {
  name               = "${local.name_prefix}-api-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.api_deploy_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-deploy-role"
  })
}

data "aws_iam_policy_document" "api_deploy" {
  statement {
    sid       = "EcrAuthorization"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PublishApiImage"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.api.arn]
  }

  statement {
    sid    = "ReadAndUpdateApiService"
    effect = "Allow"
    actions = [
      "ecs:DescribeServices",
      "ecs:UpdateService",
    ]
    resources = [
      "arn:aws:ecs:${var.aws_region}:141145164743:service/${aws_ecs_cluster.main.name}/${aws_ecs_service.api.name}",
    ]
  }

  statement {
    sid       = "ReadTaskDefinitions"
    effect    = "Allow"
    actions   = ["ecs:DescribeTaskDefinition"]
    resources = ["*"]
  }

  statement {
    sid       = "RegisterApiTaskDefinition"
    effect    = "Allow"
    actions   = ["ecs:RegisterTaskDefinition"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "ecs:task-cpu"
      values   = ["256"]
    }

    condition {
      test     = "StringEquals"
      variable = "ecs:task-memory"
      values   = ["512"]
    }

    condition {
      test     = "StringEquals"
      variable = "ecs:compute-compatibility"
      values   = ["FARGATE"]
    }
  }

  statement {
    sid     = "RunApiMigrationTask"
    effect  = "Allow"
    actions = ["ecs:RunTask"]
    resources = [
      "arn:aws:ecs:${var.aws_region}:141145164743:task-definition/${aws_ecs_task_definition.api.family}:*",
    ]

    condition {
      test     = "ArnEquals"
      variable = "ecs:cluster"
      values   = [aws_ecs_cluster.main.arn]
    }
  }

  statement {
    sid     = "ReadApiMigrationTask"
    effect  = "Allow"
    actions = ["ecs:DescribeTasks"]
    resources = [
      "arn:aws:ecs:${var.aws_region}:141145164743:task/${aws_ecs_cluster.main.name}/*",
    ]
  }

  statement {
    sid     = "PassExactApiTaskRoles"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.ecs_execution.arn,
      aws_iam_role.api_task.arn,
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "api_deploy" {
  name   = "${local.name_prefix}-api-deploy"
  role   = aws_iam_role.api_deploy.id
  policy = data.aws_iam_policy_document.api_deploy.json
}
