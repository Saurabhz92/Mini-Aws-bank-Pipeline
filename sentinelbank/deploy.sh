#!/bin/bash

###############################################################################
# SentinelBank Automated Deployment Script
# Deploys the complete fraud flagging pipeline to AWS
###############################################################################

set -e  # Exit on any error

# Configuration
REGION="ap-south-1"
BUCKET_NAME="sentinel-bank-transactions-vault"
SNS_TOPIC_NAME="SentinelBank-ComplianceAlerts"
EMAIL_ADDRESS="Saurabh.zanjurne92@gmail.com" 

# Function names
LAMBDA_VALIDATOR="SentinelBank-FileValidator"
LAMBDA_RISK_SCORER="SentinelBank-RiskScorer"
STEPFUNCTIONS_NAME="SentinelBank-CompliancePipeline"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "🏦 SentinelBank Deployment Script"
echo "======================================"
echo ""

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"
echo "Region: $REGION"
echo ""

# Step 1: Create S3 Bucket
echo -e "${YELLOW}[1/9] Creating S3 Bucket...${NC}"
if aws s3 ls "s3://$BUCKET_NAME" 2>&1 | grep -q 'NoSuchBucket'; then
    aws s3api create-bucket \
        --bucket $BUCKET_NAME \
        --region $REGION \
        --create-bucket-configuration LocationConstraint=$REGION
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket $BUCKET_NAME \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket $BUCKET_NAME \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket $BUCKET_NAME \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    echo -e "${GREEN}✅ Bucket created with security enabled${NC}"
else
    echo -e "${GREEN}✅ Bucket already exists${NC}"
fi

# Create folder structure
echo "Creating folder structure..."
touch empty.txt
aws s3 cp empty.txt s3://$BUCKET_NAME/inbound/.keep
aws s3 cp empty.txt s3://$BUCKET_NAME/audit-high-risk/.keep
aws s3 cp empty.txt s3://$BUCKET_NAME/archive-cleared/.keep
rm empty.txt
echo ""

# Step 2: Create SNS Topic
echo -e "${YELLOW}[2/9] Creating SNS Topic...${NC}"
SNS_TOPIC_ARN=$(aws sns create-topic \
    --name $SNS_TOPIC_NAME \
    --region $REGION \
    --query 'TopicArn' \
    --output text 2>/dev/null || aws sns list-topics --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text)

echo "SNS Topic ARN: $SNS_TOPIC_ARN"

# Subscribe email
echo "Subscribing email: $EMAIL_ADDRESS"
aws sns subscribe \
    --topic-arn $SNS_TOPIC_ARN \
    --protocol email \
    --notification-endpoint $EMAIL_ADDRESS \
    --region $REGION

echo -e "${GREEN}✅ SNS topic created (check email to confirm subscription)${NC}"
echo ""

# Step 3: Create IAM Role for Lambda
echo -e "${YELLOW}[3/9] Creating IAM Role for Lambda...${NC}"
cat > lambda-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
    --role-name SentinelBank-LambdaExecutionRole \
    --assume-role-policy-document file://lambda-trust-policy.json \
    2>/dev/null || echo "Role already exists"

# Attach policy
aws iam put-role-policy \
    --role-name SentinelBank-LambdaExecutionRole \
    --policy-name SentinelBank-LambdaPolicy \
    --policy-document file://iam_policies/lambda_iam_policy.json

echo -e "${GREEN}✅ Lambda IAM role created${NC}"
echo ""

# Step 4: Package and Deploy Lambda Functions
echo -e "${YELLOW}[4/9] Packaging Lambda Functions...${NC}"

# Package File Validator
mkdir -p lambda_packages
cd lambda_packages
cp ../lambda_file_validator.py .
zip -r lambda_file_validator.zip lambda_file_validator.py
cd ..

# Package Risk Scorer
cd lambda_packages
cp ../lambda_risk_scorer.py .
zip -r lambda_risk_scorer.zip lambda_risk_scorer.py
cd ..

echo -e "${GREEN}✅ Lambda packages created${NC}"
echo ""

# Step 5: Create Lambda Functions
echo -e "${YELLOW}[5/9] Creating Lambda Functions...${NC}"

LAMBDA_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/SentinelBank-LambdaExecutionRole"

# Wait for role to propagate
echo "Waiting for IAM role to propagate..."
sleep 10

# Create File Validator
aws lambda create-function \
    --function-name $LAMBDA_VALIDATOR \
    --runtime python3.11 \
    --role $LAMBDA_ROLE_ARN \
    --handler lambda_file_validator.lambda_handler \
    --zip-file fileb://lambda_packages/lambda_file_validator.zip \
    --timeout 30 \
    --memory-size 256 \
    --region $REGION \
    2>/dev/null || aws lambda update-function-code \
    --function-name $LAMBDA_VALIDATOR \
    --zip-file fileb://lambda_packages/lambda_file_validator.zip \
    --region $REGION

# Create Risk Scorer
aws lambda create-function \
    --function-name $LAMBDA_RISK_SCORER \
    --runtime python3.11 \
    --role $LAMBDA_ROLE_ARN \
    --handler lambda_risk_scorer.lambda_handler \
    --zip-file fileb://lambda_packages/lambda_risk_scorer.zip \
    --timeout 60 \
    --memory-size 512 \
    --region $REGION \
    2>/dev/null || aws lambda update-function-code \
    --function-name $LAMBDA_RISK_SCORER \
    --zip-file fileb://lambda_packages/lambda_risk_scorer.zip \
    --region $REGION

echo -e "${GREEN}✅ Lambda functions deployed${NC}"
echo ""

# Step 6: Create IAM Role for Step Functions
echo -e "${YELLOW}[6/9] Creating IAM Role for Step Functions...${NC}"
cat > stepfunctions-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "states.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
    --role-name SentinelBank-StepFunctionsRole \
    --assume-role-policy-document file://stepfunctions-trust-policy.json \
    2>/dev/null || echo "Role already exists"

# Attach policy
aws iam put-role-policy \
    --role-name SentinelBank-StepFunctionsRole \
    --policy-name SentinelBank-StepFunctionsPolicy \
    --policy-document file://iam_policies/stepfunctions_iam_policy.json

echo -e "${GREEN}✅ Step Functions IAM role created${NC}"
echo ""

# Step 7: Update and Create Step Functions State Machine
echo -e "${YELLOW}[7/9] Creating Step Functions State Machine...${NC}"

# Replace placeholders in state machine definition
sed "s/ACCOUNT_ID/$ACCOUNT_ID/g" stepfunctions_statemachine.json > stepfunctions_updated.json

STEPFUNCTIONS_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/SentinelBank-StepFunctionsRole"

# Wait for role to propagate
sleep 10

aws stepfunctions create-state-machine \
    --name $STEPFUNCTIONS_NAME \
    --definition file://stepfunctions_updated.json \
    --role-arn $STEPFUNCTIONS_ROLE_ARN \
    --region $REGION \
    2>/dev/null || aws stepfunctions update-state-machine \
    --state-machine-arn "arn:aws:states:$REGION:$ACCOUNT_ID:stateMachine:$STEPFUNCTIONS_NAME" \
    --definition file://stepfunctions_updated.json \
    --role-arn $STEPFUNCTIONS_ROLE_ARN \
    --region $REGION

echo -e "${GREEN}✅ Step Functions state machine deployed${NC}"
echo ""

# Step 8: Create EC2 IAM Role
echo -e "${YELLOW}[8/9] Creating IAM Role for EC2...${NC}"
cat > ec2-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
    --role-name SentinelBank-EC2Role \
    --assume-role-policy-document file://ec2-trust-policy.json \
    2>/dev/null || echo "Role already exists"

# Attach policy
aws iam put-role-policy \
    --role-name SentinelBank-EC2Role \
    --policy-name SentinelBank-EC2Policy \
    --policy-document file://iam_policies/ec2_iam_policy.json

# Create instance profile
aws iam create-instance-profile \
    --instance-profile-name SentinelBank-EC2InstanceProfile \
    2>/dev/null || echo "Instance profile already exists"

aws iam add-role-to-instance-profile \
    --instance-profile-name SentinelBank-EC2InstanceProfile \
    --role-name SentinelBank-EC2Role \
    2>/dev/null || echo "Role already attached"

echo -e "${GREEN}✅ EC2 IAM role created${NC}"
echo ""

# Step 9: Summary
echo -e "${YELLOW}[9/9] Deployment Summary${NC}"
echo "======================================"
echo -e "${GREEN}✅ All components deployed successfully!${NC}"
echo ""
echo "📋 Resources Created:"
echo "  • S3 Bucket: $BUCKET_NAME"
echo "  • SNS Topic: $SNS_TOPIC_ARN"
echo "  • Lambda Functions:"
echo "    - $LAMBDA_VALIDATOR"
echo "    - $LAMBDA_RISK_SCORER"
echo "  • Step Functions: $STEPFUNCTIONS_NAME"
echo "  • IAM Roles:"
echo "    - SentinelBank-LambdaExecutionRole"
echo "    - SentinelBank-StepFunctionsRole"
echo "    - SentinelBank-EC2Role"
echo ""
echo "⚠️  Next Steps:"
echo "1. Check your email and confirm SNS subscription"
echo "2. Test the pipeline manually:"
echo "   python transaction_generator.py --records 100"
echo "3. Trigger Step Functions execution from AWS Console"
echo "4. (Optional) Launch EC2 instance with SentinelBank-EC2InstanceProfile"
echo ""
echo "======================================"

# Cleanup temporary files
rm -f lambda-trust-policy.json stepfunctions-trust-policy.json ec2-trust-policy.json stepfunctions_updated.json
