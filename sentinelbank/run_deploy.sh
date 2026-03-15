#!/bin/bash

# Add AWS CLI to PATH for this session
export PATH=$PATH:/c/Program\ Files/Amazon/AWSCLIV2/

# Verify AWS CLI is available
echo "Checking AWS CLI..."
aws --version

# Run deployment
echo ""
echo "Starting deployment..."
bash deploy.sh
