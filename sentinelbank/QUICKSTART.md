# SentinelBank Quick Reference Guide

## 🚀 Common Commands

### Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Generate test data (no upload)
python transaction_generator.py --records 100 --no-upload

# Generate with specific risk percentage
python transaction_generator.py --records 500 --high-risk-percentage 30

# Run local tests
python test_pipeline.py
```

### AWS Deployment

```bash
# Full deployment (run once)
chmod +x deploy.sh
./deploy.sh

# Update Lambda code only
cd lambda_packages
zip -r lambda_file_validator.zip lambda_file_validator.py
aws lambda update-function-code \
  --function-name SentinelBank-FileValidator \
  --zip-file fileb://lambda_file_validator.zip \
  --region ap-south-1
```

### Manual Testing on AWS

```bash
# Upload test file
python transaction_generator.py --records 200 --high-risk-percentage 25

# Trigger Step Functions manually
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:ap-south-1:ACCOUNT_ID:stateMachine:SentinelBank-CompliancePipeline \
  --input '{"bucket":"sentinel-bank-transactions-vault","s3Key":"inbound/daily_transactions_TIMESTAMP.csv"}' \
  --region ap-south-1

# Check execution status
aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:ap-south-1:ACCOUNT_ID:stateMachine:SentinelBank-CompliancePipeline \
  --region ap-south-1

# View Lambda logs
aws logs tail /aws/lambda/SentinelBank-FileValidator --follow --region ap-south-1
aws logs tail /aws/lambda/SentinelBank-RiskScorer --follow --region ap-south-1
```

### S3 Operations

```bash
# List files in each folder
aws s3 ls s3://sentinel-bank-transactions-vault/inbound/
aws s3 ls s3://sentinel-bank-transactions-vault/audit-high-risk/
aws s3 ls s3://sentinel-bank-transactions-vault/archive-cleared/

# Download a file for review
aws s3 cp s3://sentinel-bank-transactions-vault/audit-high-risk/daily_transactions.csv . --region ap-south-1
```

---

## 🔍 Troubleshooting

### Issue: SNS Email Not Received

**Solution:**
```bash
# Check subscription status
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:ap-south-1:ACCOUNT_ID:SentinelBank-ComplianceAlerts \
  --region ap-south-1

# Resubscribe if needed
aws sns subscribe \
  --topic-arn arn:aws:sns:ap-south-1:ACCOUNT_ID:SentinelBank-ComplianceAlerts \
  --protocol email \
  --notification-endpoint your-email@example.com \
  --region ap-south-1
```

### Issue: Lambda Permission Errors

**Solution:**
```bash
# Verify IAM role attached
aws lambda get-function --function-name SentinelBank-FileValidator --region ap-south-1 | grep Role

# Update IAM policy
aws iam put-role-policy \
  --role-name SentinelBank-LambdaExecutionRole \
  --policy-name SentinelBank-LambdaPolicy \
  --policy-document file://iam_policies/lambda_iam_policy.json
```

### Issue: Step Functions Execution Failed

**Solution:**
```bash
# Get execution details
aws stepfunctions describe-execution \
  --execution-arn arn:aws:states:ap-south-1:ACCOUNT_ID:execution:SentinelBank-CompliancePipeline:EXECUTION_ID \
  --region ap-south-1

# Check CloudWatch Logs for Lambda errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/SentinelBank-RiskScorer \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --region ap-south-1
```

---

## 📊 Architecture Decisions

### Why Step Functions vs. Simple Lambda?

- **Pros**:
  - Visual workflow for compliance audits
  - Built-in retry and error handling
  - State management for long-running processes
  - Easy to add approval steps (future)

- **Cons**:
  - More expensive for high-volume (use Lambda + SQS if >1M transactions/day)
  - Slight latency overhead

### Why Batch CSV vs. Real-Time?

- **Current**: CSV batch processing (regional branches upload daily)
- **Future**: Kinesis Data Streams for real-time transaction monitoring

### Security Best Practices Implemented

1. **Least Privilege IAM**: Each component has minimal permissions
2. **Encryption**: S3 server-side encryption (AES-256)
3. **No Hardcoded Secrets**: Uses IAM roles instead of access keys
4. **Synthetic Data**: Faker library prevents PII exposure
5. **Versioning**: S3 versioning for audit trail

---

## 🎯 Interview Preparation

### Key Metrics to Mention

- **Processing Time**: ~5-10 seconds per 500 transaction file
- **Cost**: $3-5/month for moderate usage
- **Scalability**: Can handle 10,000+ files/day with auto-scaling
- **Accuracy**: 100% rule-based detection (no false negatives on configured rules)

### Technical Deep Dive Questions

**Q: How would you handle duplicate transactions?**  
A: Add a DynamoDB table to track processed transaction IDs. Use PutItem with ConditionalCheckFailedException to detect duplicates.

**Q: What if the Lambda function times out on large files?**  
A: 
1. Increase timeout and memory (current: 60s, 512MB)
2. Process in chunks using S3 Select
3. For very large files, trigger Step Functions Map state to parallelize

**Q: How do you prevent false positives?**  
A: 
1. Implement whitelisting for known high-value legitimate transactions
2. Add velocity checks (e.g., only flag if 3+ high-risk in 1 hour)
3. Future: ML model to learn normal behavior patterns

**Q: How would you add a manual approval step?**  
A: Add a Task state with SNS and use Step Functions' Task Token pattern. Wait for human approval via API Gateway callback.

---

## 📈 Future Enhancements (Roadmap)

### Phase 2: ML Integration
- Train SageMaker model on historical fraud data
- Replace rule-based with anomaly detection
- A/B test ML vs. rules performance

### Phase 3: Real-Time Processing
- Migrate CSV → Kinesis Data Streams
- Use Lambda for sub-second flagging
- Add DynamoDB for transaction deduplication

### Phase 4: Advanced Analytics
- QuickSight dashboard for compliance metrics
- Track precision/recall of flagging rules
- Regional risk heatmaps

### Phase 5: Multi-Region Compliance
- Handle GDPR (EU) vs. US regulations
- Cross-region replication for DR
- Data residency compliance

---

## 🛠️ Maintenance

### Monthly Tasks
- [ ] Review CloudWatch Logs for errors
- [ ] Check S3 storage costs (archive old files to Glacier)
- [ ] Validate SNS email delivery metrics
- [ ] Update high-risk country list based on sanctions

### Quarterly Tasks
- [ ] Review IAM policies for least privilege
- [ ] Update Lambda runtime if new version available
- [ ] Performance testing with peak volume
- [ ] Cost optimization review

---

## 📞 Support

For issues or questions:
1. Check CloudWatch Logs first
2. Review this guide's troubleshooting section
3. Check AWS Service Health Dashboard
4. Review Step Functions execution history

---

**Last Updated**: 2026-02-07  
**Version**: 1.0.0  
**Maintained By**: Cloud Engineering Team
