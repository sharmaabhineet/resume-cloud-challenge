"""
Cost Kill Switch Lambda
Triggered by SNS when AWS Budget threshold is breached.
Sets reserved concurrency = 0 on all at-risk Lambdas and disables their EventBridge rules.
Reversible: re-enable by removing reserved concurrency and re-enabling rules.
"""
import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Populated from environment variables set in Terraform
LAMBDAS_TO_THROTTLE = [x.strip() for x in os.environ.get("LAMBDAS_TO_THROTTLE", "").split(",") if x.strip()]
EVENTBRIDGE_RULES_TO_DISABLE = [x.strip() for x in os.environ.get("EVENTBRIDGE_RULES_TO_DISABLE", "").split(",") if x.strip()]
NOTIFY_TOPIC_ARN = os.environ.get("NOTIFY_TOPIC_ARN", "")
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"


def handler(event, context):
    logger.info("Kill switch triggered. DRY_RUN=%s", DRY_RUN)
    logger.info("SNS event: %s", json.dumps(event))

    lam = boto3.client("lambda")
    eb = boto3.client("events")
    sns = boto3.client("sns")

    throttled = []
    skipped_lambda = []
    disabled_rules = []
    skipped_rules = []
    errors = []

    for fn in LAMBDAS_TO_THROTTLE:
        try:
            if DRY_RUN:
                logger.info("[DRY RUN] Would throttle Lambda: %s", fn)
                throttled.append(fn)
            else:
                lam.put_function_concurrency(FunctionName=fn, ReservedConcurrentExecutions=0)
                logger.info("Throttled Lambda: %s", fn)
                throttled.append(fn)
        except lam.exceptions.ResourceNotFoundException:
            logger.warning("Lambda not found (skipping): %s", fn)
            skipped_lambda.append(fn)
        except Exception as e:
            logger.error("Failed to throttle %s: %s", fn, e)
            errors.append(f"lambda:{fn} — {e}")

    for rule in EVENTBRIDGE_RULES_TO_DISABLE:
        try:
            if DRY_RUN:
                logger.info("[DRY RUN] Would disable EventBridge rule: %s", rule)
                disabled_rules.append(rule)
            else:
                eb.disable_rule(Name=rule)
                logger.info("Disabled EventBridge rule: %s", rule)
                disabled_rules.append(rule)
        except eb.exceptions.ResourceNotFoundException:
            logger.warning("EventBridge rule not found (skipping): %s", rule)
            skipped_rules.append(rule)
        except Exception as e:
            logger.error("Failed to disable rule %s: %s", rule, e)
            errors.append(f"rule:{rule} — {e}")

    summary = (
        f"{'[DRY RUN] ' if DRY_RUN else ''}"
        f"Cost kill switch activated.\n\n"
        f"Lambdas throttled (concurrency=0): {throttled or 'none'}\n"
        f"EventBridge rules disabled: {disabled_rules or 'none'}\n"
        f"Skipped (not found): lambdas={skipped_lambda}, rules={skipped_rules}\n"
        f"Errors: {errors or 'none'}\n\n"
        f"To restore: remove reserved concurrency and re-enable EventBridge rules."
    )
    logger.info(summary)

    if NOTIFY_TOPIC_ARN:
        try:
            sns.publish(
                TopicArn=NOTIFY_TOPIC_ARN,
                Subject="[AWS] Cost Kill Switch Activated",
                Message=summary,
            )
        except Exception as e:
            logger.error("Failed to send SNS notification: %s", e)

    return {
        "status": "dry_run" if DRY_RUN else "activated",
        "throttled": throttled,
        "disabled_rules": disabled_rules,
        "skipped_lambda": skipped_lambda,
        "skipped_rules": skipped_rules,
        "errors": errors,
    }
