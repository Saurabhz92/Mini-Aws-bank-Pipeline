"""
SentinelBank Transaction Generator
Generates realistic banking transaction data with intentional suspicious patterns
for testing the fraud detection pipeline.

Author: Cloud Engineering Team
Date: 2026-02-07
"""

import csv
import random
import argparse
from datetime import datetime
from faker import Faker
import boto3
from botocore.exceptions import ClientError

# Initialize Faker for data generation
fake = Faker()

# Banking configuration
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
SAFE_COUNTRIES = ['USA', 'UK', 'Germany', 'France', 'Japan', 'Singapore', 'Switzerland', 'Canada', 'Australia', 'Netherlands']
TRANSACTION_TYPES = ['TRANSFER', 'WITHDRAWAL', 'DEPOSIT']
HIGH_RISK_THRESHOLD = 10000  # Amount in USD

# AWS Configuration
S3_BUCKET = 'sentinel-bank-transactions-vault'
S3_INBOUND_PREFIX = 'inbound/'
REGION = 'ap-south-1'


def generate_transaction_record(force_high_risk=False):
    """
    Generate a single transaction record.
    
    Args:
        force_high_risk (bool): If True, generates a high-risk transaction
        
    Returns:
        dict: Transaction record
    """
    if force_high_risk:
        # Generate a suspicious transaction
        if random.choice([True, False]):
            # High amount transaction
            amount = random.randint(HIGH_RISK_THRESHOLD + 1000, 50000)
            country = random.choice(SAFE_COUNTRIES + HIGH_RISK_COUNTRIES)
        else:
            # Sanctioned country transaction
            amount = random.randint(100, HIGH_RISK_THRESHOLD - 1000)
            country = random.choice(HIGH_RISK_COUNTRIES)
    else:
        # Generate a normal transaction
        amount = random.randint(10, 9500)
        country = random.choice(SAFE_COUNTRIES)
    
    return {
        'tx_id': fake.uuid4(),
        'account_no': fake.iban(),
        'amount': amount,
        'country': country,
        'type': random.choice(TRANSACTION_TYPES),
        'timestamp': datetime.now().isoformat()
    }


def generate_banking_data(records=100, high_risk_percentage=15, output_file='daily_transactions.csv'):
    """
    Generate a batch of banking transactions.
    
    Args:
        records (int): Total number of transactions to generate
        high_risk_percentage (int): Percentage of high-risk transactions (0-100)
        output_file (str): Output CSV filename
        
    Returns:
        tuple: (filename, high_risk_count, total_count)
    """
    print(f"🏦 Generating {records} banking transactions...")
    print(f"📊 Target high-risk percentage: {high_risk_percentage}%")
    
    # Calculate how many high-risk transactions to inject
    high_risk_count = int((high_risk_percentage / 100) * records)
    
    # Create positions for high-risk transactions (randomize placement)
    high_risk_positions = set(random.sample(range(records), high_risk_count))
    
    transactions = []
    actual_high_risk = 0
    
    for i in range(records):
        force_high_risk = i in high_risk_positions
        transaction = generate_transaction_record(force_high_risk)
        transactions.append(transaction)
        
        # Track actual high-risk transactions based on business rules
        if transaction['amount'] > HIGH_RISK_THRESHOLD or transaction['country'] in HIGH_RISK_COUNTRIES:
            actual_high_risk += 1
    
    # Write to CSV
    fieldnames = ['tx_id', 'account_no', 'amount', 'country', 'type', 'timestamp']
    
    with open(output_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(transactions)
    
    print(f"✅ Generated {records} transactions")
    print(f"⚠️  High-risk transactions: {actual_high_risk} ({(actual_high_risk/records)*100:.1f}%)")
    print(f"💾 Saved to: {output_file}")
    
    return output_file, actual_high_risk, records


def upload_to_s3(filename, bucket=S3_BUCKET, prefix=S3_INBOUND_PREFIX):
    """
    Upload the generated CSV file to S3 inbound bucket.
    
    Args:
        filename (str): Local file path
        bucket (str): S3 bucket name
        prefix (str): S3 key prefix
        
    Returns:
        bool: True if successful, False otherwise
    """
    s3_key = f"{prefix}{filename}"
    
    try:
        print(f"\n🚀 Uploading to S3...")
        print(f"   Bucket: {bucket}")
        print(f"   Key: {s3_key}")
        
        s3_client = boto3.client('s3', region_name=REGION)
        
        # Upload file
        s3_client.upload_file(
            filename,
            bucket,
            s3_key,
            ExtraArgs={'ServerSideEncryption': 'AES256'}
        )
        
        print(f"✅ Upload successful!")
        print(f"   S3 URI: s3://{bucket}/{s3_key}")
        
        return True
        
    except ClientError as e:
        print(f"❌ Upload failed: {e}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False


def main():
    """Main execution function."""
    parser = argparse.ArgumentParser(
        description='Generate banking transaction data for SentinelBank fraud detection testing'
    )
    parser.add_argument(
        '--records',
        type=int,
        default=500,
        help='Number of transaction records to generate (default: 500)'
    )
    parser.add_argument(
        '--high-risk-percentage',
        type=int,
        default=15,
        help='Percentage of high-risk transactions to inject (default: 15)'
    )
    parser.add_argument(
        '--output',
        type=str,
        default=f'daily_transactions_{datetime.now().strftime("%Y%m%d_%H%M%S")}.csv',
        help='Output filename (default: daily_transactions_TIMESTAMP.csv)'
    )
    parser.add_argument(
        '--upload',
        action='store_true',
        help='Upload to S3 after generation'
    )
    parser.add_argument(
        '--no-upload',
        action='store_true',
        help='Skip S3 upload (for local testing)'
    )
    
    args = parser.parse_args()
    
    # Validate arguments
    if args.high_risk_percentage < 0 or args.high_risk_percentage > 100:
        print("❌ Error: high-risk-percentage must be between 0 and 100")
        return
    
    print("=" * 60)
    print("🏦 SentinelBank Transaction Generator")
    print("=" * 60)
    
    # Generate data
    filename, high_risk_count, total_count = generate_banking_data(
        records=args.records,
        high_risk_percentage=args.high_risk_percentage,
        output_file=args.output
    )
    
    # Upload to S3 if requested (default is to upload unless --no-upload is specified)
    if not args.no_upload:
        success = upload_to_s3(filename)
        if success:
            print("\n🎉 Transaction batch ready for compliance review!")
        else:
            print("\n⚠️  File generated locally but S3 upload failed")
            print("   Check AWS credentials and bucket permissions")
    else:
        print("\n💾 File generated locally (upload skipped)")
    
    print("=" * 60)


if __name__ == '__main__':
    main()
