# SentinelBank Deployment Script for PowerShell
# Deploys the complete fraud flagging pipeline to AWS

# Configuration
$REGION = "ap-south-1"
$BUCKET_NAME = "sentinel-bank-transactions-vault"
$SNS_TOPIC_NAME = "SentinelBank-ComplianceAlerts"
$EMAIL_ADDRESS = "Saurabh.zanjurne92@gmail.com"

# Function names
$LAMBDA_VALIDATOR = "SentinelBank-FileValidator"
$LAMBDA_RISK_SCORER = "SentinelBank-RiskScorer"
$STEPFUNCTIONS_NAME = "SentinelBank-CompliancePipeline"

Write-Host "======================================"
Write-Host "🏦 SentinelBank Deployment Script"
Write-Host "======================================"
Write-Host ""

# Get AWS Account ID
try {
    $ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)
    Write-Host "AWS Account ID: $ACCOUNT_ID"
    Write-Host "Region: $REGION"
    Write-Host ""
} catch {
    Write-Host "❌ Error: AWS CLI not found or not configured"
    Write-Host "Please run: aws configure"
    exit 1
}

# Step 1: Create S3 Bucket
Write-Host "[1/9] Creating S3 Bucket..." -ForegroundColor Yellow

try {
    aws s3api create-bucket `
        --bucket $BUCKET_NAME `
        --region $REGION `
        --create-bucket-configuration LocationConstraint=$REGION 2>$null
    
    # Enable versioning
    aws s3api put-bucket-versioning `
        --bucket $BUCKET_NAME `
        --versioning-configuration Status=Enabled
    
    # Enable encryption  
    $encryptionConfig = @{
        "Rules" = @(
            @{
                "ApplyServerSideEncryptionByDefault" = @{
                    "SSEAlgorithm" = "AES256"
                }
            }
        )
    } | ConvertTo-Json -Compress -Depth 10
    
    aws s3api put-bucket-encryption `
        --bucket $BUCKET_NAME `
        --server-side-encryption-configuration $encryptionConfig
    
    # Block public access
    aws s3api put-public-access-block `
        --bucket $BUCKET_NAME `
        --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    Write-Host "✅ Bucket created with security enabled" -ForegroundColor Green
} catch {
    Write-Host "✅ Bucket already exists" -ForegroundColor Green
}

# Create folder structure
Write-Host "Creating folder structure..."
"" | Out-File empty.txt
aws s3 cp empty.txt s3://$BUCKET_NAME/inbound/.keep
aws s3 cp empty.txt s3://$BUCKET_NAME/audit-high-risk/.keep
aws s3 cp empty.txt s3://$BUCKET_NAME/archive-cleared/.keep
Remove-Item empty.txt
Write-Host ""

# Step 2: Create SNS Topic
Write-Host "[2/9] Creating SNS Topic..." -ForegroundColor Yellow

$SNS_TOPIC_ARN = (aws sns create-topic `
    --name $SNS_TOPIC_NAME `
    --region $REGION `
    --query 'TopicArn' `
    --output text 2>$null)

if (-not $SNS_TOPIC_ARN) {
    $SNS_TOPIC_ARN = (aws sns list-topics --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text)
}

Write-Host "SNS Topic ARN: $SNS_TOPIC_ARN"

# Subscribe email
Write-Host "Subscribing email: $EMAIL_ADDRESS"
aws sns subscribe `
    --topic-arn $SNS_TOPIC_ARN `
    --protocol email `
    --notification-endpoint $EMAIL_ADDRESS `
    --region $REGION

Write-Host "✅ SNS topic created (check email to confirm subscription)" -ForegroundColor Green
Write-Host ""

# Step 3: Create IAM Role for Lambda
Write-Host "[3/9] Creating IAM Role for Lambda..." -ForegroundColor Yellow

$lambdaTrustPolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
"@

$lambdaTrustPolicy | Out-File lambda-trust-policy.json -Encoding utf8

aws iam create-role `
    --role-name SentinelBank-LambdaExecutionRole `
    --assume-role-policy-document file://lambda-trust-policy.json 2>$null

# Attach policy
aws iam put-role-policy `
    --role-name SentinelBank-LambdaExecutionRole `
    --policy-name SentinelBank-LambdaPolicy `
    --policy-document file://iam_policies/lambda_iam_policy.json

Write-Host "✅ Lambda IAM role created" -ForegroundColor Green
Write-Host ""

# Step 4: Package Lambda Functions
Write-Host "[4/9] Packaging Lambda Functions..." -ForegroundColor Yellow

# Create directory
New-Item -ItemType Directory -Force -Path lambda_packages | Out-Null

# Package File Validator
Copy-Item lambda_file_validator.py lambda_packages/
Compress-Archive -Path lambda_packages/lambda_file_validator.py -DestinationPath lambda_packages/lambda_file_validator.zip -Force

# Package Risk Scorer  
Copy-Item lambda_risk_scorer.py lambda_packages/
Compress-Archive -Path lambda_packages/lambda_risk_scorer.py -DestinationPath lambda_packages/lambda_risk_scorer.zip -Force

Write-Host "✅ Lambda packages created" -ForegroundColor Green
Write-Host ""

# Step 5: Create Lambda Functions
Write-Host "[5/9] Creating Lambda Functions..." -ForegroundColor Yellow

$LAMBDA_ROLE_ARN = "arn:aws:iam::${ACCOUNT_ID}:role/SentinelBank-LambdaExecutionRole"

# Wait for role to propagate
Write-Host "Waiting for IAM role to propagate..."
Start-Sleep -Seconds 10

# Create File Validator
aws lambda create-function `
    --function-name $LAMBDA_VALIDATOR `
    --runtime python3.11 `
    --role $LAMBDA_ROLE_ARN `
    --handler lambda_file_validator.lambda_handler `
    --zip-file fileb://lambda_packages/lambda_file_validator.zip `
    --timeout 30 `
    --memory-size 256 `
    --region $REGION 2>$null

if ($LASTEXITCODE -ne 0) {
    aws lambda update-function-code `
        --function-name $LAMBDA_VALIDATOR `
        --zip-file fileb://lambda_packages/lambda_file_validator.zip `
        --region $REGION
}

# Create Risk Scorer
aws lambda create-function `
    --function-name $LAMBDA_RISK_SCORER `
    --runtime python3.11 `
    --role $LAMBDA_ROLE_ARN `
    --handler lambda_risk_scorer.lambda_handler `
    --zip-file fileb://lambda_packages/lambda_risk_scorer.zip `
    --timeout 60 `
    --memory-size 512 `
    --region $REGION 2>$null

if ($LASTEXITCODE -ne 0) {
    aws lambda update-function-code `
        --function-name $LAMBDA_RISK_SCORER `
        --zip-file fileb://lambda_packages/lambda_risk_scorer.zip `
        --region $REGION
}

Write-Host "✅ Lambda functions deployed" -ForegroundColor Green
Write-Host ""

# Step 6: Create IAM Role for Step Functions
Write-Host "[6/9] Creating IAM Role for Step Functions..." -ForegroundColor Yellow

$stepfunctionsTrustPolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "states.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
"@

$stepfunctionsTrustPolicy | Out-File stepfunctions-trust-policy.json -Encoding utf8

aws iam create-role `
    --role-name SentinelBank-StepFunctionsRole `
    --assume-role-policy-document file://stepfunctions-trust-policy.json 2>$null

# Attach policy
aws iam put-role-policy `
    --role-name SentinelBank-StepFunctionsRole `
    --policy-name SentinelBank-StepFunctionsPolicy `
    --policy-document file://iam_policies/stepfunctions_iam_policy.json

Write-Host "✅ Step Functions IAM role created" -ForegroundColor Green
Write-Host ""

# Step 7: Create Step Functions State Machine
Write-Host "[7/9] Creating Step Functions State Machine..." -ForegroundColor Yellow

# Replace ACCOUNT_ID in state machine definition
$statemachine = Get-Content stepfunctions_statemachine.json -Raw
$statemachine = $statemachine.Replace("ACCOUNT_ID", $ACCOUNT_ID)
$statemachine | Out-File stepfunctions_updated.json -Encoding utf8

$STEPFUNCTIONS_ROLE_ARN = "arn:aws:iam::${ACCOUNT_ID}:role/SentinelBank-StepFunctionsRole"

# Wait for role to propagate
Start-Sleep -Seconds 10

aws stepfunctions create-state-machine `
    --name $STEPFUNCTIONS_NAME `
    --definition file://stepfunctions_updated.json `
    --role-arn $STEPFUNCTIONS_ROLE_ARN `
    --region $REGION 2>$null

if ($LASTEXITCODE -ne 0) {
    aws stepfunctions update-state-machine `
        --state-machine-arn "arn:aws:states:${REGION}:${ACCOUNT_ID}:stateMachine:$STEPFUNCTIONS_NAME" `
        --definition file://stepfunctions_updated.json `
        --role-arn $STEPFUNCTIONS_ROLE_ARN `
        --region $REGION
}

Write-Host "✅ Step Functions state machine deployed" -ForegroundColor Green
Write-Host ""

# Step 8: Create EC2 IAM Role
Write-Host "[8/9] Creating IAM Role for EC2..." -ForegroundColor Yellow

$ec2TrustPolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
"@

$ec2TrustPolicy | Out-File ec2-trust-policy.json -Encoding utf8

aws iam create-role `
    --role-name SentinelBank-EC2Role `
    --assume-role-policy-document file://ec2-trust-policy.json 2>$null

# Attach policy
aws iam put-role-policy `
    --role-name SentinelBank-EC2Role `
    --policy-name SentinelBank-EC2Policy `
    --policy-document file://iam_policies/ec2_iam_policy.json

# Create instance profile
aws iam create-instance-profile `
    --instance-profile-name SentinelBank-EC2InstanceProfile 2>$null

aws iam add-role-to-instance-profile `
    --instance-profile-name SentinelBank-EC2InstanceProfile `
    --role-name SentinelBank-EC2Role 2>$null

Write-Host "✅ EC2 IAM role created" -ForegroundColor Green
Write-Host ""

# Step 9: Summary
Write-Host "[9/9] Deployment Summary" -ForegroundColor Yellow
Write-Host "======================================"
Write-Host "✅ All components deployed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Resources Created:"
Write-Host "  • S3 Bucket: $BUCKET_NAME"
Write-Host "  • SNS Topic: $SNS_TOPIC_ARN"
Write-Host "  • Lambda Functions:"
Write-Host "    - $LAMBDA_VALIDATOR"
Write-Host "    - $LAMBDA_RISK_SCORER"
Write-Host "  • Step Functions: $STEPFUNCTIONS_NAME"
Write-Host "  • IAM Roles:"
Write-Host "    - SentinelBank-LambdaExecutionRole"
Write-Host "    - SentinelBank-StepFunctionsRole"
Write-Host "    - SentinelBank-EC2Role"
Write-Host ""
Write-Host "⚠️  Next Steps:"
Write-Host "1. Check your email and confirm SNS subscription"
Write-Host "2. Test the pipeline manually:"
Write-Host "   python transaction_generator.py --records 100"
Write-Host "3. Trigger Step Functions execution from AWS Console"
Write-Host "4. (Optional) Launch EC2 instance with SentinelBank-EC2InstanceProfile"
Write-Host ""
Write-Host "======================================"

# Cleanup temporary files
Remove-Item lambda-trust-policy.json -ErrorAction SilentlyContinue
Remove-Item stepfunctions-trust-policy.json -ErrorAction SilentlyContinue
Remove-Item ec2-trust-policy.json -ErrorAction SilentlyContinue
Remove-Item stepfunctions_updated.json -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "✅ Deployment complete! Check your email for SNS confirmation." -ForegroundColor Green
