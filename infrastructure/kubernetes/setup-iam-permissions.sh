#!/bin/bash

echo "🔐 Setting up IAM permissions for Pod Identity..."

# Check if Pod Identity associations exist
echo "📋 Checking existing Pod Identity associations..."
ASSOCIATIONS=$(aws eks list-pod-identity-associations --cluster-name aurora-logs-poc-cluster --namespace aurora-logs 2>/dev/null)

if [ -z "$ASSOCIATIONS" ]; then
    echo "❌ No Pod Identity associations found. Please set up Pod Identity first."
    exit 1
fi

# Get role ARNs from associations
DISCOVERY_ROLE=$(aws eks describe-pod-identity-association --cluster-name aurora-logs-poc-cluster \
    --association-id $(echo $ASSOCIATIONS | jq -r '.associations[] | select(.serviceAccount=="discovery-sa") | .associationId') \
    2>/dev/null | jq -r '.association.roleArn' | cut -d'/' -f2)

PROCESSOR_ROLE=$(aws eks describe-pod-identity-association --cluster-name aurora-logs-poc-cluster \
    --association-id $(echo $ASSOCIATIONS | jq -r '.associations[] | select(.serviceAccount=="processor-sa") | .associationId') \
    2>/dev/null | jq -r '.association.roleArn' | cut -d'/' -f2)

echo "📍 Discovery Role: $DISCOVERY_ROLE"
echo "📍 Processor Role: $PROCESSOR_ROLE"

# Create IAM policy if it doesn't exist
POLICY_NAME="aurora-log-system-policy"
POLICY_ARN="arn:aws:iam::072006186126:policy/$POLICY_NAME"

echo -e "\n📄 Checking IAM policy..."
if ! aws iam get-policy --policy-arn $POLICY_ARN &>/dev/null; then
    echo "Creating IAM policy..."
    aws iam create-policy \
        --policy-name $POLICY_NAME \
        --policy-document file://iam-policy.json \
        --description "Policy for Aurora Log System to access RDS, DynamoDB, and S3"
else
    echo "✓ IAM policy already exists"
fi

# Attach policy to roles
echo -e "\n🔗 Attaching IAM policy to roles..."

if [ -n "$DISCOVERY_ROLE" ]; then
    echo "  Attaching to Discovery role..."
    aws iam attach-role-policy \
        --role-name "$DISCOVERY_ROLE" \
        --policy-arn "$POLICY_ARN" 2>/dev/null || echo "    Already attached"
fi

if [ -n "$PROCESSOR_ROLE" ]; then
    echo "  Attaching to Processor role..."
    aws iam attach-role-policy \
        --role-name "$PROCESSOR_ROLE" \
        --policy-arn "$POLICY_ARN" 2>/dev/null || echo "    Already attached"
fi

# Verify attachments
echo -e "\n🔍 Verifying IAM permissions..."

if [ -n "$DISCOVERY_ROLE" ]; then
    DISCOVERY_POLICIES=$(aws iam list-attached-role-policies --role-name "$DISCOVERY_ROLE" | jq -r '.AttachedPolicies[].PolicyName')
    if echo "$DISCOVERY_POLICIES" | grep -q "$POLICY_NAME"; then
        echo "✅ Discovery role has correct permissions"
    else
        echo "❌ Discovery role missing permissions"
    fi
fi

if [ -n "$PROCESSOR_ROLE" ]; then
    PROCESSOR_POLICIES=$(aws iam list-attached-role-policies --role-name "$PROCESSOR_ROLE" | jq -r '.AttachedPolicies[].PolicyName')
    if echo "$PROCESSOR_POLICIES" | grep -q "$POLICY_NAME"; then
        echo "✅ Processor role has correct permissions"
    else
        echo "❌ Processor role missing permissions"
    fi
fi

echo -e "\n✅ IAM permissions setup complete"