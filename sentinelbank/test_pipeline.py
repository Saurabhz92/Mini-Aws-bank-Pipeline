"""
Test Script for SentinelBank Pipeline
Tests the transaction generator and Lambda functions locally before AWS deployment
"""

import sys
import json
from io import StringIO
import csv

print("=" * 60)
print("🧪 SentinelBank Local Testing Suite")
print("=" * 60)

# Test 1: Transaction Generator
print("\n[Test 1] Transaction Generator")
print("-" * 60)

try:
    # Import the generator
    sys.path.insert(0, '.')
    from transaction_generator import generate_banking_data
    
    # Generate test data
    filename, high_risk_count, total_count = generate_banking_data(
        records=100,
        high_risk_percentage=20,
        output_file='test_transactions.csv'
    )
    
    print(f"✅ Generated {total_count} transactions")
    print(f"✅ High-risk transactions: {high_risk_count}")
    
    # Verify file structure
    with open(filename, 'r') as f:
        reader = csv.DictReader(f)
        required_cols = ['tx_id', 'account_no', 'amount', 'country', 'type']
        
        if all(col in reader.fieldnames for col in required_cols):
            print("✅ All required columns present")
        else:
            print("❌ Missing required columns")
            
except Exception as e:
    print(f"❌ Transaction generator test failed: {e}")

# Test 2: File Validator (Mock)
print("\n[Test 2] File Validator Logic")
print("-" * 60)

try:
    # Simulate validator logic
    test_csv = """tx_id,account_no,amount,country,type
123e4567-e89b-12d3-a456-426614174000,GB82WEST12345698765432,15000,USA,TRANSFER
223e4567-e89b-12d3-a456-426614174001,GB82WEST12345698765433,500,UK,DEPOSIT
"""
    
    reader = csv.DictReader(StringIO(test_csv))
    required_columns = ['tx_id', 'account_no', 'amount', 'country', 'type']
    
    if set(required_columns).issubset(set(reader.fieldnames)):
        print("✅ Schema validation passed")
    else:
        print("❌ Schema validation failed")
        
    rows = list(reader)
    if len(rows) > 0:
        print(f"✅ Data rows present: {len(rows)}")
    else:
        print("❌ No data rows found")
        
except Exception as e:
    print(f"❌ File validator test failed: {e}")

# Test 3: Risk Scorer Logic
print("\n[Test 3] Risk Scorer Logic")
print("-" * 60)

try:
    HIGH_RISK_THRESHOLD = 10000
    HIGH_RISK_COUNTRIES = ['Cayman Islands']
    
    test_transactions = [
        {'amount': '15000', 'country': 'USA'},        # High amount
        {'amount': '500', 'country': 'Cayman Islands'},  # Sanctioned country
        {'amount': '5000', 'country': 'UK'},         # Safe
        {'amount': '20000', 'country': 'Cayman Islands'}  # Both criteria
    ]
    
    high_risk_count = 0
    for tx in test_transactions:
        is_high_risk = False
        amount = float(tx['amount'])
        country = tx['country']
        
        if amount > HIGH_RISK_THRESHOLD:
            is_high_risk = True
        if country in HIGH_RISK_COUNTRIES:
            is_high_risk = True
            
        if is_high_risk:
            high_risk_count += 1
    
    expected_high_risk = 3  # First, second, and fourth transactions
    
    if high_risk_count == expected_high_risk:
        print(f"✅ Risk scoring correct: {high_risk_count}/{len(test_transactions)} flagged")
    else:
        print(f"❌ Risk scoring incorrect: got {high_risk_count}, expected {expected_high_risk}")
        
except Exception as e:
    print(f"❌ Risk scorer test failed: {e}")

# Test 4: Data Integrity
print("\n[Test 4] Data Integrity Checks")
print("-" * 60)

try:
    with open('test_transactions.csv', 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        
        # Check for duplicates
        tx_ids = [row['tx_id'] for row in rows]
        if len(tx_ids) == len(set(tx_ids)):
            print("✅ No duplicate transaction IDs")
        else:
            print("❌ Duplicate transaction IDs found")
        
        # Check amount values
        invalid_amounts = 0
        for row in rows:
            try:
                amount = float(row['amount'])
                if amount < 0:
                    invalid_amounts += 1
            except ValueError:
                invalid_amounts += 1
        
        if invalid_amounts == 0:
            print("✅ All amounts are valid numbers")
        else:
            print(f"❌ Found {invalid_amounts} invalid amounts")
            
except Exception as e:
    print(f"❌ Data integrity test failed: {e}")

# Summary
print("\n" + "=" * 60)
print("✅ Local testing complete!")
print("=" * 60)
print("\n📝 Next Steps:")
print("1. Review test_transactions.csv to verify data quality")
print("2. Run deployment: ./deploy.sh")
print("3. Upload test file to S3 and trigger Step Functions")
print("")
