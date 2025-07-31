#!/bin/bash
# Script to empty DynamoDB tables before terraform destroy
# This preserves the tables but removes all data

set -e

REGION="us-east-1"
TABLES=(
    "aurora-instance-metadata"
    "aurora-log-file-tracking"
    "aurora-log-processing-jobs"
)

echo "⚠️  WARNING: This will DELETE ALL DATA from the DynamoDB tables!"
echo "Tables to be emptied:"
for table in "${TABLES[@]}"; do
    echo "  - $table"
done
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Operation cancelled."
    exit 0
fi

for table in "${TABLES[@]}"; do
    echo ""
    echo "Processing table: $table"
    
    # Get the key schema
    KEY_SCHEMA=$(aws dynamodb describe-table --table-name "$table" --region "$REGION" --query 'Table.KeySchema' --output json)
    
    # Determine the keys
    HASH_KEY=$(echo "$KEY_SCHEMA" | jq -r '.[] | select(.KeyType == "HASH") | .AttributeName')
    RANGE_KEY=$(echo "$KEY_SCHEMA" | jq -r '.[] | select(.KeyType == "RANGE") | .AttributeName // empty')
    
    echo "  Hash key: $HASH_KEY"
    if [ -n "$RANGE_KEY" ]; then
        echo "  Range key: $RANGE_KEY"
    fi
    
    # Scan and delete all items
    echo "  Scanning and deleting items..."
    
    SCAN_OUTPUT="/tmp/${table}_scan.json"
    DELETE_COUNT=0
    
    while true; do
        # Scan the table
        if [ -f "$SCAN_OUTPUT" ] && [ -s "$SCAN_OUTPUT" ]; then
            # Continue from last evaluated key
            LAST_KEY=$(jq -r '.LastEvaluatedKey // empty' "$SCAN_OUTPUT")
            if [ -z "$LAST_KEY" ]; then
                break
            fi
            aws dynamodb scan \
                --table-name "$table" \
                --region "$REGION" \
                --exclusive-start-key "$LAST_KEY" \
                --output json > "$SCAN_OUTPUT"
        else
            # First scan
            aws dynamodb scan \
                --table-name "$table" \
                --region "$REGION" \
                --output json > "$SCAN_OUTPUT"
        fi
        
        # Extract items and delete them
        if [ -n "$RANGE_KEY" ]; then
            # Table has both hash and range key
            jq -c '.Items[]' "$SCAN_OUTPUT" | while read -r item; do
                HASH_VALUE=$(echo "$item" | jq -r ".${HASH_KEY}")
                RANGE_VALUE=$(echo "$item" | jq -r ".${RANGE_KEY}")
                
                aws dynamodb delete-item \
                    --table-name "$table" \
                    --region "$REGION" \
                    --key "{\"${HASH_KEY}\": ${HASH_VALUE}, \"${RANGE_KEY}\": ${RANGE_VALUE}}" \
                    >/dev/null 2>&1
                
                ((DELETE_COUNT++))
                if [ $((DELETE_COUNT % 25)) -eq 0 ]; then
                    echo "    Deleted $DELETE_COUNT items..."
                fi
            done
        else
            # Table has only hash key
            jq -c '.Items[]' "$SCAN_OUTPUT" | while read -r item; do
                HASH_VALUE=$(echo "$item" | jq -r ".${HASH_KEY}")
                
                aws dynamodb delete-item \
                    --table-name "$table" \
                    --region "$REGION" \
                    --key "{\"${HASH_KEY}\": ${HASH_VALUE}}" \
                    >/dev/null 2>&1
                
                ((DELETE_COUNT++))
                if [ $((DELETE_COUNT % 25)) -eq 0 ]; then
                    echo "    Deleted $DELETE_COUNT items..."
                fi
            done
        fi
        
        # Check if more items to scan
        if ! jq -e '.LastEvaluatedKey' "$SCAN_OUTPUT" >/dev/null 2>&1; then
            break
        fi
    done
    
    echo "  ✓ Deleted $DELETE_COUNT items from $table"
    rm -f "$SCAN_OUTPUT"
done

echo ""
echo "✅ All DynamoDB tables have been emptied successfully!"
echo ""
echo "You can now safely run 'terraform destroy' without deleting the table structures."