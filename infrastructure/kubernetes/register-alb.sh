#!/bin/bash
# Register OpenObserve pod with existing ALB target group

set -e

# Configuration
ALB_ARN="arn:aws:elasticloadbalancing:us-east-1:072006186126:loadbalancer/app/openobserve-alb/e5b34856b41f3d36"
REGION="us-east-1"
NAMESPACE="aurora-logs"

echo "Registering OpenObserve with existing ALB..."

# Get target group ARN
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
  --load-balancer-arn $ALB_ARN \
  --region $REGION \
  --output json | jq -r '.TargetGroups[0].TargetGroupArn')

echo "Target Group ARN: $TARGET_GROUP_ARN"

# Get OpenObserve pod IP
POD_IP=$(kubectl get pod -n $NAMESPACE -l app=openobserve -o jsonpath='{.items[0].status.podIP}')

if [ -z "$POD_IP" ]; then
  echo "ERROR: No OpenObserve pod found"
  exit 1
fi

echo "OpenObserve Pod IP: $POD_IP"

# Deregister any existing targets
echo "Deregistering existing targets..."
EXISTING_TARGETS=$(aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN \
  --region $REGION \
  --output json | jq -r '.TargetHealthDescriptions[].Target.Id')

for target in $EXISTING_TARGETS; do
  aws elbv2 deregister-targets \
    --target-group-arn $TARGET_GROUP_ARN \
    --targets Id=$target \
    --region $REGION || true
done

# Register new target
echo "Registering OpenObserve pod with ALB..."
aws elbv2 register-targets \
  --target-group-arn $TARGET_GROUP_ARN \
  --targets Id=$POD_IP \
  --region $REGION

# Check target health
echo "Checking target health..."
sleep 5
aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP_ARN \
  --region $REGION \
  --output table

echo ""
echo "OpenObserve is now accessible at:"
echo "http://openobserve-alb-355407172.us-east-1.elb.amazonaws.com"
echo ""
echo "Default credentials:"
echo "Username: admin@example.com"
echo "Password: Complexpass#123"