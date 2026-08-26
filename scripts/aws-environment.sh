#!/usr/bin/env bash
set -Eeuo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-production}"
EXPECTED_ACCOUNT_ID="141145164743"
EXPECTED_REGION="us-east-1"
EXPECTED_ENVIRONMENT="production"
NAME_PREFIX="quadra-${ENVIRONMENT}"
RDS_IDENTIFIER="${NAME_PREFIX}-db"
ECS_CLUSTER="${NAME_PREFIX}-ecs-cluster"
ECS_SERVICE="${NAME_PREFIX}-api-service"
TARGET_GROUP_NAME="${NAME_PREFIX}-api-tg"
SCHEDULE_NAME="${NAME_PREFIX}-rds-stop"
SCHEDULE_GROUP="default"
HEALTH_URL="https://api.appquadra.com.br/health"
TARGET_GROUP_ARN=""

COLOR_BLUE=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_RED=""
COLOR_RESET=""
if [[ -z "${NO_COLOR:-}" && ( -t 1 || "${CLICOLOR_FORCE:-0}" == 1 ) ]]; then
  COLOR_BLUE=$'\033[34m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_RED=$'\033[31m'
  COLOR_RESET=$'\033[0m'
fi

usage() {
  printf 'Usage: %s status|pause|resume\n' "${0##*/}" >&2
}

log_message() {
  local color="$1" label="$2"
  shift 2
  printf '%s[%(%H:%M:%S)T] [%s] %s%s\n' \
    "$color" -1 "$label" "$*" "$COLOR_RESET"
}

fail() {
  local code="$1"
  shift
  log_message "$COLOR_RED" ERROR "$*" >&2
  exit "$code"
}

aws_cli() {
  aws --no-cli-pager --region "$AWS_REGION" "$@"
}

rds_status() {
  local status
  status="$(aws_cli rds describe-db-instances \
    --db-instance-identifier "$RDS_IDENTIFIER" \
    --query 'DBInstances[0].DBInstanceStatus' --output text)" ||
    fail 1 "failed to query RDS $RDS_IDENTIFIER"
  [[ -n "$status" && "$status" != None ]] ||
    fail 1 "RDS $RDS_IDENTIFIER was not found"
  printf '%s\n' "$status"
}

wait_for_rds_stopped() {
  local label="$1" status attempt
  for ((attempt = 1; attempt <= 60; attempt++)); do
    status="$(rds_status)"
    case "$status" in
      stopped) return 0 ;;
      stopping)
        log_message "$COLOR_YELLOW" "$label" \
          'RDS state: stopping; waiting for stopped...'
        ;;
      *) fail 2 "RDS entered unsupported state while stopping: $status" ;;
    esac
    sleep 30
  done
  fail 2 'RDS did not reach stopped within 30 minutes'
}

ecs_counts() {
  local counts
  counts="$(aws_cli ecs describe-services \
    --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
    --query 'services[0].[desiredCount,runningCount,pendingCount]' --output text)" ||
    fail 1 "failed to query ECS service $ECS_SERVICE"
  [[ "$counts" =~ ^[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+$ ]] ||
    fail 1 "invalid ECS counts for $ECS_SERVICE: $counts"
  printf '%s\n' "$counts"
}

scheduler_state() {
  local state
  state="$(aws_cli scheduler get-schedule \
    --name "$SCHEDULE_NAME" --group-name "$SCHEDULE_GROUP" \
    --query State --output text)" ||
    fail 1 "failed to query Scheduler $SCHEDULE_NAME"
  [[ "$state" == ENABLED || "$state" == DISABLED ]] ||
    fail 1 "invalid Scheduler state for $SCHEDULE_NAME: $state"
  printf '%s\n' "$state"
}

target_counts() {
  local counts
  counts="$(aws_cli elbv2 describe-target-health \
    --target-group-arn "$TARGET_GROUP_ARN" \
    --query "[length(TargetHealthDescriptions[?TargetHealth.State=='healthy']), length(TargetHealthDescriptions)]" \
    --output text)" || fail 1 "failed to query target health for $TARGET_GROUP_NAME"
  [[ "$counts" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]] ||
    fail 1 "invalid target counts for $TARGET_GROUP_NAME: $counts"
  printf '%s\n' "$counts"
}

validate_context() {
  command -v aws >/dev/null || fail 1 'aws CLI was not found in PATH'
  command -v curl >/dev/null || fail 1 'curl was not found in PATH'
  [[ "$AWS_REGION" == "$EXPECTED_REGION" ]] ||
    fail 1 "refusing region $AWS_REGION; expected $EXPECTED_REGION"
  [[ "$ENVIRONMENT" == "$EXPECTED_ENVIRONMENT" ]] ||
    fail 1 "refusing environment $ENVIRONMENT; expected $EXPECTED_ENVIRONMENT"

  local account_id
  account_id="$(aws_cli sts get-caller-identity --query Account --output text)" ||
    fail 1 'failed to resolve the current AWS account'
  [[ "$account_id" == "$EXPECTED_ACCOUNT_ID" ]] ||
    fail 1 "refusing account $account_id; expected $EXPECTED_ACCOUNT_ID"

  TARGET_GROUP_ARN="$(aws_cli elbv2 describe-target-groups \
    --names "$TARGET_GROUP_NAME" --query 'TargetGroups[0].TargetGroupArn' \
    --output text)" || fail 1 "failed to query target group $TARGET_GROUP_NAME"
  [[ -n "$TARGET_GROUP_ARN" && "$TARGET_GROUP_ARN" != None ]] ||
    fail 1 "target group $TARGET_GROUP_NAME was not found"

  rds_status >/dev/null
  ecs_counts >/dev/null
  scheduler_state >/dev/null
}

update_scheduler_state() {
  local requested_state="$1" expression window target actual_state
  expression="$(aws_cli scheduler get-schedule \
    --name "$SCHEDULE_NAME" --group-name "$SCHEDULE_GROUP" \
    --query ScheduleExpression --output text)" ||
    fail 1 "failed to read Scheduler expression for $SCHEDULE_NAME"
  window="$(aws_cli scheduler get-schedule \
    --name "$SCHEDULE_NAME" --group-name "$SCHEDULE_GROUP" \
    --query FlexibleTimeWindow --output json)" ||
    fail 1 "failed to read Scheduler window for $SCHEDULE_NAME"
  target="$(aws_cli scheduler get-schedule \
    --name "$SCHEDULE_NAME" --group-name "$SCHEDULE_GROUP" \
    --query Target --output json)" ||
    fail 1 "failed to read Scheduler target for $SCHEDULE_NAME"

  if ! aws_cli scheduler update-schedule \
    --name "$SCHEDULE_NAME" \
    --group-name "$SCHEDULE_GROUP" \
    --schedule-expression "$expression" \
    --schedule-expression-timezone UTC \
    --flexible-time-window "$window" \
    --target "$target" \
    --state "$requested_state" >/dev/null; then
    if [[ "$requested_state" == ENABLED ]]; then
      fail 1 'environment is paused, but the RDS restart protection could not be enabled'
    fi
    fail 1 "failed to set Scheduler $SCHEDULE_NAME to $requested_state"
  fi

  actual_state="$(scheduler_state)"
  [[ "$actual_state" == "$requested_state" ]] ||
    fail 2 "Scheduler is $actual_state; expected $requested_state"
  printf 'Scheduler: %s\n' "$actual_state"
}

show_status() {
  local rds scheduler desired running pending healthy=0 total=0 http_status=skipped
  rds="$(rds_status)"
  scheduler="$(scheduler_state)"
  read -r desired running pending <<<"$(ecs_counts)"
  read -r healthy total <<<"$(target_counts)"

  if ((desired > 0 || running > 0 || pending > 0)); then
    http_status="$(curl --fail --silent --show-error \
      --output /dev/null --write-out '%{http_code}' "$HEALTH_URL")" ||
      fail 1 "health check failed for $HEALTH_URL"
  fi

  printf 'RDS: %s\n' "$rds"
  printf 'ECS: desired=%s running=%s pending=%s\n' "$desired" "$running" "$pending"
  printf 'Scheduler: %s\n' "$scheduler"
  printf 'Targets: healthy=%s total=%s\n' "$healthy" "$total"
  printf 'Health check: %s%s\n' "$([[ "$http_status" == skipped ]] && printf '' || printf 'HTTP ')" "$http_status"

  if [[ "$rds" == available && "$desired" == 1 && "$running" == 1 && "$pending" == 0 &&
        "$scheduler" == DISABLED && "$healthy" -ge 1 && "$http_status" == 200 ]]; then
    printf 'Environment: RUNNING\n'
    return 0
  fi
  if [[ "$rds" == stopped && "$desired" == 0 && "$running" == 0 && "$pending" == 0 &&
        "$scheduler" == ENABLED ]]; then
    printf 'Environment: PAUSED\n'
    return 0
  fi
  if [[ "$rds" == starting || "$rds" == stopping || "$pending" -gt 0 ]]; then
    printf 'Environment: TRANSITIONING\n'
  else
    printf 'Environment: INCONSISTENT\n'
  fi
  return 2
}

pause_environment() {
  local rds desired running pending
  rds="$(rds_status)"
  log_message "$COLOR_BLUE" '1/4' 'Scaling ECS service to zero...'

  aws_cli ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" \
    --desired-count 0 >/dev/null || fail 1 'failed to scale ECS to zero'
  log_message "$COLOR_YELLOW" '1/4' 'Waiting for ECS service stability...'
  aws_cli ecs wait services-stable --cluster "$ECS_CLUSTER" \
    --services "$ECS_SERVICE" || fail 1 'ECS did not stabilize at zero'
  read -r desired running pending <<<"$(ecs_counts)"
  [[ "$desired" == 0 && "$running" == 0 && "$pending" == 0 ]] ||
    fail 2 "ECS did not reach zero: desired=$desired running=$running pending=$pending"
  log_message "$COLOR_GREEN" '1/4' \
    "ECS stopped: desired=$desired running=$running pending=$pending"

  log_message "$COLOR_BLUE" '2/4' "RDS initial state: $rds"

  case "$rds" in
    available)
      log_message "$COLOR_BLUE" '2/4' 'Requesting RDS stop...'
      rds="$(aws_cli rds stop-db-instance \
        --db-instance-identifier "$RDS_IDENTIFIER" \
        --query 'DBInstance.DBInstanceStatus' --output text)" ||
        fail 1 "failed to stop RDS $RDS_IDENTIFIER"
      ;;
    starting)
      log_message "$COLOR_YELLOW" '2/4' \
        'Waiting for RDS to become available before stopping...'
      aws_cli rds wait db-instance-available \
        --db-instance-identifier "$RDS_IDENTIFIER" ||
        fail 2 "RDS did not become available before pause"
      log_message "$COLOR_BLUE" '2/4' 'Requesting RDS stop...'
      rds="$(aws_cli rds stop-db-instance \
        --db-instance-identifier "$RDS_IDENTIFIER" \
        --query 'DBInstance.DBInstanceStatus' --output text)" ||
        fail 1 "failed to stop RDS $RDS_IDENTIFIER"
      ;;
    stopping|stopped) ;;
    *) fail 2 "unsupported RDS state: $rds" ;;
  esac
  log_message "$COLOR_YELLOW" '2/4' "RDS transition state: $rds"

  log_message "$COLOR_YELLOW" '2/4' 'Waiting for RDS to reach stopped...'
  wait_for_rds_stopped '2/4'
  rds="$(rds_status)"
  [[ "$rds" == stopped ]] || fail 2 "RDS is $rds; expected stopped"
  log_message "$COLOR_GREEN" '2/4' 'RDS stopped.'

  log_message "$COLOR_BLUE" '3/4' 'Enabling RDS stop Scheduler...'
  update_scheduler_state ENABLED
  log_message "$COLOR_GREEN" '3/4' 'RDS stop Scheduler enabled.'
  log_message "$COLOR_YELLOW" '4/4' 'Verifying paused environment...'
  show_status
  log_message "$COLOR_GREEN" '4/4' 'Pause complete.'
}

resume_environment() {
  local rds desired running pending healthy total http_status
  log_message "$COLOR_BLUE" '1/4' 'Disabling RDS stop Scheduler...'
  update_scheduler_state DISABLED
  log_message "$COLOR_GREEN" '1/4' 'RDS stop Scheduler disabled.'
  rds="$(rds_status)"
  log_message "$COLOR_BLUE" '2/4' "RDS initial state: $rds"

  case "$rds" in
    stopped)
      log_message "$COLOR_BLUE" '2/4' 'Requesting RDS start...'
      rds="$(aws_cli rds start-db-instance \
        --db-instance-identifier "$RDS_IDENTIFIER" \
        --query 'DBInstance.DBInstanceStatus' --output text)" ||
        fail 1 "failed to start RDS $RDS_IDENTIFIER"
      ;;
    stopping)
      log_message "$COLOR_YELLOW" '2/4' \
        'Waiting for RDS to finish stopping before restart...'
      wait_for_rds_stopped '2/4'
      log_message "$COLOR_BLUE" '2/4' 'Requesting RDS start...'
      rds="$(aws_cli rds start-db-instance \
        --db-instance-identifier "$RDS_IDENTIFIER" \
        --query 'DBInstance.DBInstanceStatus' --output text)" ||
        fail 1 "failed to start RDS $RDS_IDENTIFIER"
      ;;
    starting|available) ;;
    *) fail 2 "unsupported RDS state: $rds" ;;
  esac
  log_message "$COLOR_YELLOW" '2/4' "RDS transition state: $rds"

  log_message "$COLOR_YELLOW" '2/4' 'Waiting for RDS to reach available...'
  aws_cli rds wait db-instance-available \
    --db-instance-identifier "$RDS_IDENTIFIER" ||
    fail 2 "RDS did not reach available"
  rds="$(rds_status)"
  [[ "$rds" == available ]] || fail 2 "RDS is $rds; expected available"
  log_message "$COLOR_GREEN" '2/4' 'RDS available.'

  log_message "$COLOR_BLUE" '3/4' 'Scaling ECS service to one task...'
  aws_cli ecs update-service --cluster "$ECS_CLUSTER" --service "$ECS_SERVICE" \
    --desired-count 1 >/dev/null || fail 1 'failed to scale ECS to one'
  log_message "$COLOR_YELLOW" '3/4' 'Waiting for ECS service stability...'
  aws_cli ecs wait services-stable --cluster "$ECS_CLUSTER" \
    --services "$ECS_SERVICE" || fail 2 'ECS did not become stable'
  read -r desired running pending <<<"$(ecs_counts)"
  [[ "$desired" == 1 && "$running" == 1 && "$pending" == 0 ]] ||
    fail 2 "ECS is not ready: desired=$desired running=$running pending=$pending"
  log_message "$COLOR_GREEN" '3/4' \
    "ECS ready: desired=$desired running=$running pending=$pending"

  log_message "$COLOR_YELLOW" '4/4' 'Waiting for a healthy target...'
  aws_cli elbv2 wait target-in-service --target-group-arn "$TARGET_GROUP_ARN" ||
    fail 2 'target did not become healthy'
  read -r healthy total <<<"$(target_counts)"
  ((healthy >= 1)) || fail 2 "no healthy target: healthy=$healthy total=$total"
  log_message "$COLOR_YELLOW" '4/4' "Checking $HEALTH_URL..."
  http_status="$(curl --fail --silent --show-error \
    --output /dev/null --write-out '%{http_code}' "$HEALTH_URL")" ||
    fail 1 "health check failed for $HEALTH_URL"
  [[ "$http_status" == 200 ]] || fail 2 "health check returned HTTP $http_status"

  log_message "$COLOR_YELLOW" '4/4' 'Verifying running environment...'
  show_status
  log_message "$COLOR_GREEN" '4/4' 'Resume complete.'
}

main() {
  (($# == 1)) || { usage; exit 1; }
  case "$1" in
    status|pause|resume) ;;
    *) usage; exit 1 ;;
  esac

  validate_context
  case "$1" in
    status)
      log_message "$COLOR_BLUE" STATUS 'Reading environment state...'
      show_status
      ;;
    pause) pause_environment ;;
    resume) resume_environment ;;
  esac
}

main "$@"
