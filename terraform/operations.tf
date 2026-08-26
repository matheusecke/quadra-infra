data "aws_iam_policy_document" "rds_stop_scheduler_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = ["141145164743"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:scheduler:${var.aws_region}:141145164743:schedule-group/default"]
    }
  }
}

resource "aws_iam_role" "rds_stop_scheduler" {
  name               = "${local.name_prefix}-rds-stop-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.rds_stop_scheduler_assume_role.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-stop-scheduler-role"
  })
}

data "aws_iam_policy_document" "rds_stop_scheduler" {
  statement {
    effect    = "Allow"
    actions   = ["rds:StopDBInstance"]
    resources = [aws_db_instance.main.arn]
  }
}

resource "aws_iam_role_policy" "rds_stop_scheduler" {
  name   = "${local.name_prefix}-rds-stop-scheduler"
  role   = aws_iam_role.rds_stop_scheduler.id
  policy = data.aws_iam_policy_document.rds_stop_scheduler.json
}

resource "aws_scheduler_schedule" "rds_stop" {
  name                         = "${local.name_prefix}-rds-stop"
  group_name                   = "default"
  schedule_expression          = "cron(0 3 * * ? *)"
  schedule_expression_timezone = "UTC"
  state                        = "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:stopDBInstance"
    role_arn = aws_iam_role.rds_stop_scheduler.arn
    input = jsonencode({
      DbInstanceIdentifier = aws_db_instance.main.identifier
    })

    retry_policy {
      maximum_retry_attempts = 0
    }
  }

  lifecycle {
    # Pause and resume own this operational switch after initial provisioning.
    ignore_changes = [state]
  }
}
