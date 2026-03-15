#!/bin/bash

###############################################################################
# SentinelBank EC2 Bootstrap Script
# Sets up Python environment and automated transaction generation
###############################################################################

set -e  # Exit on any error

echo "======================================"
echo "SentinelBank EC2 Setup Starting..."
echo "======================================"

# Update system packages
echo "Updating system packages..."
sudo yum update -y

# Install Python 3.11
echo "Installing Python 3.11..."
sudo yum install -y python3.11 python3.11-pip

# Create symbolic links
sudo ln -sf /usr/bin/python3.11 /usr/bin/python3
sudo ln -sf /usr/bin/pip3.11 /usr/bin/pip3

# Verify Python version
python3 --version

# Install required Python packages
echo "Installing Python dependencies..."
pip3 install --upgrade pip
pip3 install faker boto3

# Create application directory
echo "Creating application directory..."
mkdir -p /home/ec2-user/sentinelbank
cd /home/ec2-user/sentinelbank

# Download transaction generator script (if using S3 for deployment)
# Uncomment if you're storing the script in S3
# aws s3 cp s3://your-deployment-bucket/transaction_generator.py . --region ap-south-1

# Set file permissions
chmod +x transaction_generator.py

# Create log directory
mkdir -p /var/log/sentinelbank
sudo chown ec2-user:ec2-user /var/log/sentinelbank

# Set up daily cron job (runs at 2 AM IST)
echo "Setting up cron job for daily execution..."
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/bin/python3 /home/ec2-user/sentinelbank/transaction_generator.py --records 500 --high-risk-percentage 15 >> /var/log/sentinelbank/cron.log 2>&1") | crontab -

# Verify cron job
echo "Cron jobs configured:"
crontab -l

echo "======================================"
echo "✅ EC2 Setup Complete!"
echo "======================================"
echo ""
echo "Next Steps:"
echo "1. Copy transaction_generator.py to /home/ec2-user/sentinelbank/"
echo "2. Test manually: python3 transaction_generator.py --records 100 --no-upload"
echo "3. Configure AWS credentials if not using instance role"
echo ""
echo "The script will automatically run daily at 2 AM IST"
echo "======================================"
