# src/common/schema.py

from typing import Any, Dict

from jsonschema import ValidationError, validate

from src.common.logging import logger


def validate_row_data(data: Dict[str, Any], schema: Dict[str, Any]) -> bool:
    """
    Validates a dictionary of row data against a given JSON schema.

    Purpose:
        To ensure that data read from the Google Sheet conforms to our
        predefined data contract (`product_row.schema.json`) before it is
        processed further down the pipeline. This prevents bad data from
        triggering downstream failures.

    Args:
        data (Dict[str, Any]): The dictionary representing a single row of data.
        schema (Dict[str, Any]): The JSON schema to validate against.

    Returns:
        bool: True if the data is valid according to the schema, False otherwise.
    """
    try:
        validate(instance=data, schema=schema)
        logger.debug("Row data validation successful.", extra={"data": data})
        return True
    except ValidationError as e:
        # We log this as a warning because it's an expected failure mode for
        # bad data, not a system error.
        logger.warning(
            "Row data failed validation.",
            extra={
                "data": data,
                "error_message": e.message,
                "validator": e.validator,
                "validator_value": e.validator_value,
                "path": list(e.path),
            },
        )
        return False
    except Exception as e:
        # Catch any other unexpected errors during validation.
        logger.error(
            "An unexpected error occurred during schema validation.",
            extra={"error": str(e)},
        )
        return False
