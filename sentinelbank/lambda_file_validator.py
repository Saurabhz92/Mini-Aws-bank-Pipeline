"""
Lambda Function: File Validator
Validates incoming CSV files for schema compliance and data integrity.

Trigger: AWS Step Functions
Input: S3 object key
Output: Validation result with error details
"""

import json
import csv
import boto3
from io import StringIO

# Configuration
REQUIRED_COLUMNS = ['tx_id', 'account_no', 'amount', 'country', 'type']
MAX_FILE_SIZE_MB = 50
MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_MB * 1024 * 1024

# Initialize AWS clients
s3_client = boto3.client('s3')


def lambda_handler(event, context):
    """
    Main Lambda handler for file validation.
    
    Args:
        event (dict): Step Functions input containing S3 details
        context: Lambda context object
        
    Returns:
        dict: Validation result
    """
    try:
        # Extract S3 information from event
        bucket = event.get('bucket', 'sentinel-bank-transactions-vault')
        s3_key = event.get('s3Key') or event.get('key')
        
        if not s3_key:
            return {
                'isValid': False,
                'errors': ['Missing S3 key in event'],
                's3Key': None
            }
        
        print(f"Validating file: s3://{bucket}/{s3_key}")
        
        # Perform validation
        validation_result = validate_transaction_file(bucket, s3_key)
        
        # Add S3 key to result for next step
        validation_result['s3Key'] = s3_key
        validation_result['bucket'] = bucket
        
        print(f"Validation result: {validation_result}")
        
        return validation_result
        
    except Exception as e:
        print(f"Error in file validation: {str(e)}")
        return {
            'isValid': False,
            'errors': [f'Unexpected error: {str(e)}'],
            's3Key': s3_key if 's3_key' in locals() else None
        }


def validate_transaction_file(bucket, s3_key):
    """
    Validate the transaction CSV file.
    
    Args:
        bucket (str): S3 bucket name
        s3_key (str): S3 object key
        
    Returns:
        dict: Validation result with errors if any
    """
    errors = []
    
    # Check 1: File extension
    if not s3_key.lower().endswith('.csv'):
        errors.append('File must be a CSV file (.csv extension)')
        return {'isValid': False, 'errors': errors}
    
    try:
        # Get file metadata
        response = s3_client.head_object(Bucket=bucket, Key=s3_key)
        file_size = response['ContentLength']
        
        # Check 2: File size
        if file_size == 0:
            errors.append('File is empty')
            return {'isValid': False, 'errors': errors}
        
        if file_size > MAX_FILE_SIZE_BYTES:
            errors.append(f'File size ({file_size/1024/1024:.2f}MB) exceeds maximum allowed ({MAX_FILE_SIZE_MB}MB)')
            return {'isValid': False, 'errors': errors}
        
        # Download and validate content
        obj = s3_client.get_object(Bucket=bucket, Key=s3_key)
        content = obj['Body'].read().decode('utf-8')
        
        # Check 3: Parse CSV
        csv_reader = csv.DictReader(StringIO(content))
        
        # Check 4: Required columns
        if csv_reader.fieldnames is None:
            errors.append('CSV file has no header row')
            return {'isValid': False, 'errors': errors}
        
        missing_columns = set(REQUIRED_COLUMNS) - set(csv_reader.fieldnames)
        if missing_columns:
            errors.append(f'Missing required columns: {", ".join(missing_columns)}')
            return {'isValid': False, 'errors': errors}
        
        # Check 5: At least one data row
        rows = list(csv_reader)
        if len(rows) == 0:
            errors.append('CSV file has no data rows')
            return {'isValid': False, 'errors': errors}
        
        # Check 6: Full data validation across all rows
        row_errors = []
        for idx, row in enumerate(rows, start=2):  # Check ALL rows
            # Validate amount is numeric
            try:
                amount = float(row.get('amount', ''))
                if amount < 0:
                    row_errors.append(f'Row {idx}: Negative amount not allowed')
            except ValueError:
                row_errors.append(f'Row {idx}: Invalid amount value')

            # Validate required fields are not empty
            for col in REQUIRED_COLUMNS:
                if not row.get(col, '').strip():
                    row_errors.append(f'Row {idx}: Empty value for required field "{col}"')

        if row_errors:
            total_errors = len(row_errors)
            errors.extend(row_errors[:10])  # Report first 10 errors max
            if total_errors > 10:
                errors.append(f'... and {total_errors - 10} more row error(s) not shown')
            return {'isValid': False, 'errors': errors, 'totalRowErrors': total_errors}
        
        # All validations passed
        return {
            'isValid': True,
            'errors': [],
            'metadata': {
                'fileSizeBytes': file_size,
                'rowCount': len(rows),
                'columns': list(csv_reader.fieldnames)
            }
        }
        
    except Exception as e:
        errors.append(f'Error reading file: {str(e)}')
        return {'isValid': False, 'errors': errors}


# For local testing
if __name__ == '__main__':
    # Test event
    test_event = {
        'bucket': 'sentinel-bank-transactions-vault',
        's3Key': 'inbound/daily_transactions.csv'
    }
    
    result = lambda_handler(test_event, None)
    print(json.dumps(result, indent=2))
