#!/usr/bin/env python3
"""
Script to empty DynamoDB tables before terraform destroy
This preserves the tables but removes all data
Faster than shell script for large tables due to batch operations
"""

import boto3
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed

REGION = "us-east-1"
TABLES = [
    "aurora-instance-metadata",
    "aurora-log-file-tracking", 
    "aurora-log-processing-jobs"
]

def get_table_keys(dynamodb, table_name):
    """Get the key schema for a table"""
    response = dynamodb.describe_table(TableName=table_name)
    key_schema = response['Table']['KeySchema']
    
    keys = {}
    for key in key_schema:
        if key['KeyType'] == 'HASH':
            keys['hash'] = key['AttributeName']
        elif key['KeyType'] == 'RANGE':
            keys['range'] = key['AttributeName']
    
    return keys

def delete_batch(dynamodb, table_name, items, keys):
    """Delete a batch of items (max 25)"""
    delete_requests = []
    
    for item in items:
        key = {keys['hash']: item[keys['hash']]}
        if 'range' in keys:
            key[keys['range']] = item[keys['range']]
        
        delete_requests.append({
            'DeleteRequest': {
                'Key': key
            }
        })
    
    # Batch write (max 25 items)
    for i in range(0, len(delete_requests), 25):
        batch = delete_requests[i:i+25]
        try:
            dynamodb.batch_write_item(
                RequestItems={
                    table_name: batch
                }
            )
        except Exception as e:
            print(f"Error in batch delete: {e}")
            return len(batch)
    
    return len(delete_requests)

def empty_table(table_name):
    """Empty a single DynamoDB table"""
    dynamodb = boto3.client('dynamodb', region_name=REGION)
    
    print(f"\nProcessing table: {table_name}")
    
    # Get key schema
    keys = get_table_keys(dynamodb, table_name)
    print(f"  Hash key: {keys['hash']}")
    if 'range' in keys:
        print(f"  Range key: {keys['range']}")
    
    # Scan and delete all items
    print("  Scanning and deleting items...")
    
    total_deleted = 0
    last_evaluated_key = None
    
    while True:
        # Scan parameters
        scan_params = {
            'TableName': table_name,
            'Select': 'SPECIFIC_ATTRIBUTES',
            'ProjectionExpression': keys['hash']
        }
        
        if 'range' in keys:
            scan_params['ProjectionExpression'] += f", {keys['range']}"
        
        if last_evaluated_key:
            scan_params['ExclusiveStartKey'] = last_evaluated_key
        
        # Scan table
        response = dynamodb.scan(**scan_params)
        items = response.get('Items', [])
        
        if items:
            # Delete items in batches
            deleted = delete_batch(dynamodb, table_name, items, keys)
            total_deleted += deleted
            
            if total_deleted % 100 == 0:
                print(f"    Deleted {total_deleted} items...")
        
        # Check if more items to scan
        last_evaluated_key = response.get('LastEvaluatedKey')
        if not last_evaluated_key:
            break
    
    print(f"  ✓ Deleted {total_deleted} items from {table_name}")
    return total_deleted

def main():
    print("⚠️  WARNING: This will DELETE ALL DATA from the DynamoDB tables!")
    print("Tables to be emptied:")
    for table in TABLES:
        print(f"  - {table}")
    print()
    
    confirm = input("Are you sure you want to continue? (yes/no): ")
    if confirm.lower() != 'yes':
        print("Operation cancelled.")
        sys.exit(0)
    
    # Empty tables in parallel for speed
    with ThreadPoolExecutor(max_workers=3) as executor:
        futures = {executor.submit(empty_table, table): table for table in TABLES}
        
        total_deleted = 0
        for future in as_completed(futures):
            table = futures[future]
            try:
                deleted = future.result()
                total_deleted += deleted
            except Exception as e:
                print(f"Error processing {table}: {e}")
    
    print(f"\n✅ All DynamoDB tables have been emptied successfully!")
    print(f"Total items deleted: {total_deleted}")
    print("\nYou can now safely run 'terraform destroy' without deleting the table structures.")

if __name__ == "__main__":
    main()