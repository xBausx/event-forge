# src/common/logging.py

from aws_lambda_powertools import Logger

# ==============================================================================
# Centralized Logger Initialization
# ==============================================================================
#
# Purpose:
#   To provide a single, pre-configured instance of the AWS Lambda Powertools Logger.
#   By importing 'logger' from this module into any other module or Lambda
#   handler, we ensure that all log records share the same configuration and
#   will be part of the same structured JSON output.
#
# How it Works:
#   1. We initialize the Logger here at the module level.
#   2. In our Lambda handlers, we will load our environment-specific config
#      (e.g., from dev.yaml) and pass the service name and log level to this
#      logger instance.
#   3. Powertools automatically injects contextual information like the Lambda
#      request ID, cold start status, and memory usage into every log record.
#
# Usage in other files:
#   from src.common.logging import logger
#
#   def my_function():
#       logger.info("This is a structured log message.")
#
# ==============================================================================

logger = Logger()