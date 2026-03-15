"""
Lambda Function: Risk Scorer
Analyzes transaction files and assigns risk scores based on banking compliance rules.

Risk Criteria:
1. High Amount: Transaction amount > $10,000
2. Sanctioned Country: Destination country is Cayman Islands

Trigger: AWS Step Functions
Input: S3 object key, validation result
Output: Risk analysis with routing decision
"""

import json
import csv
import boto3
from io import StringIO
from collections import defaultdict

# Banking Compliance Configuration
# Sanctioned / high-risk jurisdictions per FATF & OFAC guidance
HIGH_RISK_COUNTRIES = [
    'Cayman Islands',
    'Iran',
    'North Korea',
    'Syria',
    'Russia',
    'Belarus',
    'Myanmar',
    'Cuba',
]
HIGH_AMOUNT_THRESHOLD = 10000  # USD

# Initialize AWS clients
s3_client = boto3.client('s3')


def lambda_handler(event, context):
    """
    Main Lambda handler for risk scoring.
    
    Args:
        event (dict): Step Functions input containing S3 details
        context: Lambda context object
        
    Returns:
        dict: Risk analysis result
    """
    try:
        # Extract S3 information
        bucket = event.get('bucket', 'sentinel-bank-transactions-vault')
        s3_key = event.get('s3Key')
        
        if not s3_key:
            raise ValueError('Missing S3 key in event')
        
        print(f"Analyzing risk for file: s3://{bucket}/{s3_key}")
        
        # Perform risk analysis
        risk_result = analyze_transaction_risk(bucket, s3_key)
        
        # Add S3 details to result
        risk_result['s3Key'] = s3_key
        risk_result['bucket'] = bucket
        
        print(f"Risk analysis complete: {risk_result['riskLevel']}")
        print(f"High-risk transactions: {risk_result['highRiskCount']} of {risk_result['totalTransactions']}")
        
        return risk_result
        
    except Exception as e:
        print(f"Error in risk scoring: {str(e)}")
        raise


def analyze_transaction_risk(bucket, s3_key):
    """
    Analyze all transactions in the file for risk factors.
    
    Args:
        bucket (str): S3 bucket name
        s3_key (str): S3 object key
        
    Returns:
        dict: Risk analysis result
    """
    # Download file from S3
    obj = s3_client.get_object(Bucket=bucket, Key=s3_key)
    content = obj['Body'].read().decode('utf-8')
    
    # Parse CSV
    csv_reader = csv.DictReader(StringIO(content))
    
    # Risk tracking
    high_risk_transactions = []
    risk_reason_counts = defaultdict(int)
    total_transactions = 0
    
    # Analyze each transaction
    for row in csv_reader:
        total_transactions += 1
        risk_reasons = []
        
        # Check 1: High Amount
        try:
            amount = float(row['amount'])
            if amount > HIGH_AMOUNT_THRESHOLD:
                risk_reasons.append('High Amount')
                risk_reason_counts['High Amount (>$10,000)'] += 1
        except (ValueError, KeyError):
            # Invalid amount - treat as potential risk
            risk_reasons.append('Invalid Amount')
            risk_reason_counts['Invalid Amount'] += 1
        
        # Check 2: Sanctioned Country
        country = row.get('country', '').strip()
        if country in HIGH_RISK_COUNTRIES:
            risk_reasons.append('Sanctioned Country')
            risk_reason_counts['Sanctioned Country'] += 1
        
        # If any risk factors found, record this transaction
        if risk_reasons:
            # Calculate numerical score for this transaction
            tx_type = row.get('type', '')
            try:
                tx_amount = float(row.get('amount', 0))
            except ValueError:
                tx_amount = 0
            score = calculate_risk_score(tx_amount, country, tx_type)

            high_risk_transactions.append({
                'tx_id': row.get('tx_id', 'UNKNOWN'),
                'amount': row.get('amount', '0'),
                'country': country,
                'type': tx_type,
                'reasons': risk_reasons,
                'riskScore': score
            })
    
    # Determine overall risk level
    high_risk_count = len(high_risk_transactions)
    risk_percentage = (high_risk_count / total_transactions * 100) if total_transactions > 0 else 0
    
    # Risk decision: If ANY high-risk transactions found, flag entire batch
    risk_level = 'HIGH' if high_risk_count > 0 else 'CLEARED'
    
    # Build detailed risk reasons summary
    risk_reasons_summary = []
    for reason, count in risk_reason_counts.items():
        risk_reasons_summary.append(f"{count} transactions - {reason}")
    
    # Calculate average risk score across flagged transactions
    avg_score = 0
    if high_risk_transactions:
        avg_score = round(sum(t['riskScore'] for t in high_risk_transactions) / len(high_risk_transactions), 1)

    # Prepare result
    result = {
        'riskLevel': risk_level,
        'highRiskCount': high_risk_count,
        'totalTransactions': total_transactions,
        'riskPercentage': round(risk_percentage, 2),
        'averageRiskScore': avg_score,
        'riskReasons': risk_reasons_summary,
        'fileName': s3_key.split('/')[-1],
        'timestamp': obj['LastModified'].isoformat() if 'LastModified' in obj else None
    }
    
    # Add sample high-risk transactions (up to 5 for notification)
    if high_risk_transactions:
        result['sampleHighRiskTx'] = high_risk_transactions[:5]
    
    return result


def calculate_risk_score(amount, country, transaction_type):
    """
    Calculate a numerical risk score (for future enhancement).
    
    Args:
        amount (float): Transaction amount
        country (str): Destination country
        transaction_type (str): Type of transaction
        
    Returns:
        int: Risk score (0-100)
    """
    score = 0
    
    # Amount-based scoring
    if amount > 50000:
        score += 50
    elif amount > HIGH_AMOUNT_THRESHOLD:
        score += 30
    
    # Country-based scoring
    if country in HIGH_RISK_COUNTRIES:
        score += 50
    
    # Transaction type (for future rules)
    if transaction_type == 'TRANSFER':
        score += 10
    
    return min(score, 100)


# For local testing
if __name__ == '__main__':
    # Test event
    test_event = {
        'bucket': 'sentinel-bank-transactions-vault',
        's3Key': 'inbound/daily_transactions.csv'
    }
    
    result = lambda_handler(test_event, None)
    print(json.dumps(result, indent=2))
