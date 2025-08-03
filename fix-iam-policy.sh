#!/bin/bash

# Update Discovery Role Policy
cat > /tmp/discovery-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "rds:DescribeDBClusters",
                "rds:DescribeDBInstances",
                "rds:DescribeDBLogFiles",
                "rds:ListTagsForResource"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query",
                "dynamodb:Scan",
                "dynamodb:BatchWriteItem"
            ],
            "Resource": [
                "arn:aws:dynamodb:us-east-1:072006186126:table/aurora-log-tracking",
                "arn:aws:dynamodb:us-east-1:072006186126:table/aurora-instance-metadata"
            ]
        }
    ]
}
EOF

# Update Processor Role Policy
cat > /tmp/processor-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "rds:DownloadDBLogFilePortion"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::company-aurora-logs-poc",
                "arn:aws:s3:::company-aurora-logs-poc/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Query"
            ],
            "Resource": [
                "arn:aws:dynamodb:us-east-1:072006186126:table/aurora-log-tracking",
                "arn:aws:dynamodb:us-east-1:072006186126:table/aurora-log-processing-jobs"
            ]
        }
    ]
}
EOF

echo "Updating IAM policies..."

# Update Discovery Role
aws iam put-role-policy \
    --role-name AuroraLogDiscoveryRole \
    --policy-name discovery-policy \
    --policy-document file:///tmp/discovery-policy.json

# Update Processor Role
aws iam put-role-policy \
    --role-name AuroraLogProcessorRole \
    --policy-name processor-policy \
    --policy-document file:///tmp/processor-policy.json

echo "IAM policies updated successfully!"
echo ""
echo "Restarting pods to pick up new permissions..."
kubectl rollout restart deployment discovery processor -n aurora-logs

echo "Done!"