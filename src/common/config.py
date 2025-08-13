# src/common/config.py

import os
import yaml
from pathlib import Path
from typing import Dict, Any, Optional

from src.common.logging import logger

_config_cache: Optional[Dict[str, Any]] = None


def load_config() -> Dict[str, Any]:
    """
    Loads the application configuration from a YAML file based on the APP_ENV
    environment variable.

    Purpose:
        To provide a centralized way of loading environment-specific settings.
        The function determines the environment (e.g., 'dev', 'staging', 'prod')
        from the `APP_ENV` OS environment variable, finds the corresponding
        `config/<env>.yaml` file, and loads it. The loaded configuration is
        cached to avoid repeated file I/O in the same Lambda execution context.

    Returns:
        Dict[str, Any]: A dictionary containing the application configuration.

    Raises:
        FileNotFoundError: If the required configuration file does not exist.
        ValueError: If the APP_ENV environment variable is not set.
    """
    global _config_cache
    if _config_cache:
        logger.debug("Returning cached configuration.")
        return _config_cache

    # Determine the environment (dev, staging, prod)
    env = os.environ.get("APP_ENV")
    if not env:
        raise ValueError("APP_ENV environment variable is not set.")

    logger.info(f"Loading configuration for environment: {env}")

    # Construct the path to the config file.
    # We assume the code is run from the root of the project or that the
    # 'config' directory is in the python path.
    # Path(__file__).resolve().parent.parent.parent gives us the project root.
    project_root = Path(__file__).resolve().parent.parent.parent
    config_path = project_root / "config" / f"{env}.yaml"

    if not config_path.is_file():
        logger.error(f"Configuration file not found at path: {config_path}")
        raise FileNotFoundError(f"Config file not found for env '{env}'")

    # Load the YAML file
    with open(config_path, "r") as f:
        try:
            config_data = yaml.safe_load(f)
            _config_cache = config_data
            logger.info("Successfully loaded and cached configuration.")
            return config_data
        except yaml.YAMLError as e:
            logger.error(f"Error parsing YAML file {config_path}: {e}")
            raise