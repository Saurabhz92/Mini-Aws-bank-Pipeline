# SentinelBank: Automated Fraud Flagging Pipeline

<p align="center">
  <img src="https://img.shields.io/badge/AWS-Step_Functions-FF9900?style=for-the-badge&logo=amazon-aws" />
  <img src="https://img.shields.io/badge/Python-3.11-3776AB?style=for-the-badge&logo=python" />
  <img src="https://img.shields.io/badge/Banking-Compliance-00A86B?style=for-the-badge" />
</p>

## 🏦 Project Overview

**SentinelBank** is a production-grade automated fraud detection pipeline designed for the banking industry. The system processes batch transaction files from regional branches, identifies high-risk transactions using compliance rules, and routes them for manual review or archival.

This project demonstrates:
- ✅ **Banking Security Knowledge** - PII protection using synthetic data
- ✅ **Complex Business Logic** - Conditional routing based on compliance rules
- ✅ **Event-Driven Architecture** - AWS Step Functions orchestration
- ✅ **Production-Ready Design** - Error handling, retry logic, encryption

---

## 🎯 Business Problem

Banks process thousands of transactions daily and must comply with anti-money laundering (AML) regulations. Manual review of all transactions is impractical. This system automates the detection of suspicious transactions based on:

1. **High-Value Transfers**: Transactions exceeding $10,000
2. **Sanctioned Regions**: Transfers to high-risk countries (e.g., Cayman Islands)

Flagged transactions are routed to compliance teams for investigation, while cleared transactions are archived for audit trails.

---

## 🏗️ Architecture

```
┌─────────────────┐
│   EC2 Instance  │
│ (Data Generator)│
└────────┬────────┘
         │ Upload CSV
         ▼
┌─────────────────┐
│  S3: /inbound/  │
└────────┬────────┘
         │ Trigger
         ▼
┌─────────────────────────┐
│   Step Functions        │
│  Compliance Workflow    │
└───┬─────────────────┬───┘
    │                 │
    ▼                 ▼
┌─────────┐     ┌──────────┐
│ Lambda  │     │ Lambda   │
│Validator│     │Risk Score│
└─────────┘     └─────┬────┘
                      │
           ┌──────────┴──────────┐
           ▼                     ▼
    ┌─────────────┐      ┌─────────────┐
    │ S3: /audit- │      │ S3: /archive│
    │ high-risk/  │      │ -cleared/   │
    └──────┬──────┘      └─────────────┘
           │
           ▼
    ┌─────────────┐
    │ SNS Alert   │
    │ (Email)     │
    └─────────────┘
```

---

## 🛠️ Tech Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Data Generation** | Python 3.11 + Faker | Generate realistic synthetic banking data |
| **Compute** | AWS EC2 | Run scheduled transaction generation |
| **Storage** | AWS S3 | Secure vault with encryption at rest |
| **Orchestration** | AWS Step Functions | Coordinate multi-step compliance workflow |
| **Processing** | AWS Lambda (Python 3.11) | Serverless validation and risk scoring |
| **Notifications** | AWS SNS | Alert compliance team of high-risk batches |
| **Security** | IAM Policies | Least-privilege access control |

---

## 📂 Project Structure

```
sentinelbank/
├── transaction_generator.py          # EC2 script to generate banking data
├── lambda_file_validator.py          # Lambda: CSV schema validation
├── lambda_risk_scorer.py              # Lambda: Risk analysis engine
├── stepfunctions_statemachine.json   # Step Functions workflow definition
├── deploy.sh                          # Automated deployment script
├── ec2_setup.sh                       # EC2 bootstrap script
├── requirements.txt                   # Python dependencies
├── iam_policies/
│   ├── ec2_iam_policy.json           # EC2 S3 upload permissions
│   ├── lambda_iam_policy.json        # Lambda execution permissions
│   └── stepfunctions_iam_policy.json # Step Functions orchestration
└── README.md                          # This file
```

---

## 🚀 Quick Start

### Prerequisites

- AWS Account with CLI configured
- Python 3.11 installed
- Bash shell (Linux/Mac) or Git Bash (Windows)

### Installation

1. **Clone the repository**
   ```bash
   cd sentinelbank
   ```

2. **Install Python dependencies**
   ```bash
   pip install -r requirements.txt
   ```

3. **Update configuration**
   - Edit `deploy.sh` and set your email address:
     ```bash
     EMAIL_ADDRESS="your-email@example.com"
     ```

4. **Deploy to AWS**
   ```bash
   chmod +x deploy.sh
   ./deploy.sh
   ```
   
   This script will:
   - Create S3 bucket with encryption and versioning
   - Set up SNS topic for alerts
   - Deploy Lambda functions
   - Create Step Functions state machine
   - Configure IAM roles and policies

5. **Confirm SNS subscription**
   - Check your email and click the confirmation link

---

## 🧪 Testing

### Generate Test Data

Create a transaction file with 20% high-risk transactions:

```bash
python transaction_generator.py --records 500 --high-risk-percentage 20
```

### Manual Step Functions Execution

1. Go to AWS Console → Step Functions
2. Select `SentinelBank-CompliancePipeline`
3. Click **Start execution**
4. Provide input:
   ```json
   {
     "bucket": "sentinel-bank-transactions-vault",
     "s3Key": "inbound/daily_transactions_20260207_203000.csv"
   }
   ```

### Expected Behavior

**For High-Risk Files:**
- File moved to `s3://sentinel-bank-transactions-vault/audit-high-risk/`
- Email sent to compliance team with details
- Step Functions execution: `HighRiskProcessed` (Success)

**For Cleared Files:**
- File moved to `s3://sentinel-bank-transactions-vault/archive-cleared/`
- No email sent
- Step Functions execution: `ClearedProcessed` (Success)

---

## 🔍 Key Features

### 1. **Data Masking & PII Protection**
- Uses `Faker` library to generate synthetic banking data
- No real customer information used
- Demonstrates understanding of banking security regulations

### 2. **Complex Business Logic**
- **Choice States** in Step Functions for conditional routing
- Multi-criteria risk assessment:
  - Amount-based flagging
  - Geographic sanctions compliance
- Extensible for additional rules (e.g., velocity checks)

### 3. **Error Handling**
- Schema validation catches corrupted files
- Retry logic with exponential backoff
- Dead-letter handling for failed executions
- CloudWatch Logs for debugging

### 4. **Production-Ready Security**
- **Encryption at Rest**: S3 server-side encryption (AES-256)
- **Encryption in Transit**: HTTPS for all API calls
- **Least Privilege IAM**: Each component has minimal required permissions
- **Versioning**: S3 versioning for audit trail

---

## 💰 Cost Estimation

For **light usage** (100 transactions/day):

| Service | Monthly Cost |
|---------|--------------|
| S3 Storage (1GB) | $0.02 |
| Step Functions (3,000 transitions) | $0.08 |
| Lambda (5,000 invocations) | $0.00 (Free Tier) |
| SNS (100 emails) | $0.00 (Free Tier) |
| EC2 (t3.micro, on-demand 1hr/day) | $3.00 |
| **Total** | **~$3.10/month** |

> 💡 Tip: Use EC2 Spot Instances or Lambda triggers instead of 24/7 EC2 to reduce costs further.

---

## 🎤 Interview Talking Points

When discussing this project in interviews, highlight:

1. **Banking Domain Knowledge**
   - "I implemented AML compliance rules based on FinCEN guidelines"
   - "Used synthetic data to protect PII, demonstrating security awareness"

2. **Architectural Decisions**
   - "Chose Step Functions over Lambda-only to handle complex stateful workflows"
   - "Implemented retry logic to handle transient S3 failures"

3. **Scalability**
   - "S3 can handle millions of files; Lambda auto-scales to process spikes"
   - "Could extend to real-time with S3 Event Notifications → EventBridge"

4. **Error Handling**
   - "Added schema validation to fail fast on corrupted data"
   - "Implemented dead-letter queues for manual investigation of failed batches"

5. **Extensibility**
   - "Easy to add new risk rules (e.g., transaction velocity, merchant category)"
   - "Could integrate with ML models for anomaly detection"

---

## 🔧 Advanced Enhancements

### Phase 2 Ideas

1. **Machine Learning Integration**
   - Use SageMaker to train anomaly detection models
   - Replace rule-based scoring with ML predictions

2. **Real-Time Processing**
   - Migrate from batch (CSV) to streaming (Kinesis)
   - Use Lambda for sub-second fraud detection

3. **Dashboard & Reporting**
   - Build QuickSight dashboard for compliance metrics
   - Track false positive rates

4. **Multi-Region Compliance**
   - Handle GDPR (EU) vs. local regulations
   - Cross-region replication for disaster recovery

---

## 📚 Clean Up

To avoid ongoing charges, delete all resources:

```bash
# Delete Step Functions
aws stepfunctions delete-state-machine \
  --state-machine-arn arn:aws:states:ap-south-1:ACCOUNT_ID:stateMachine:SentinelBank-CompliancePipeline

# Delete Lambda functions
aws lambda delete-function --function-name SentinelBank-FileValidator
aws lambda delete-function --function-name SentinelBank-RiskScorer

# Empty and delete S3 bucket
aws s3 rm s3://sentinel-bank-transactions-vault --recursive
aws s3 rb s3://sentinel-bank-transactions-vault

# Delete SNS topic
aws sns delete-topic --topic-arn arn:aws:sns:ap-south-1:ACCOUNT_ID:SentinelBank-ComplianceAlerts

# Delete IAM roles (detach policies first)
aws iam delete-role --role-name SentinelBank-LambdaExecutionRole
aws iam delete-role --role-name SentinelBank-StepFunctionsRole
aws iam delete-role --role-name SentinelBank-EC2Role
```

---

## 📞 Contact

**Project Author**: Cloud Engineering Team  
**Purpose**: Portfolio Project for Senior Cloud Engineer Role  
**Tech Stack**: AWS (Step Functions, Lambda, S3, SNS), Python 3.11  

---

## 📄 License

This is a portfolio/educational project. Feel free to use as a reference for your own learning.

---

## 🌟 Acknowledgments

- **Faker Library**: For realistic synthetic data generation
- **AWS Documentation**: Step Functions best practices
- **Banking Industry**: Compliance requirements inspiration

---

<p align="center">
  <strong>Built with ☁️ by passionate Cloud Engineers</strong>
</p>
