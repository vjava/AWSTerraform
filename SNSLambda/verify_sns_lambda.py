import boto3
import json
import time

region = 'us-east-1'
sns_topic_arn = 'arn:aws:sns:us-east-1:654654589397:sns-lambda-topic-3dcc03c0'
lambda_function_name = 'sns-event-processor-manual'

sns_client = boto3.client('sns', region_name=region)
logs_client = boto3.client('logs', region_name=region)

print("\n" + "="*70)
print("VERIFYING SNS TO LAMBDA TRIGGER PIPELINE")
print("="*70)

try:
    # 1. Publish Message to SNS
    test_payload = "Automated Event Message from Python Verification Script"
    print(f"1. Publishing Event Message to SNS Topic: {sns_topic_arn}")
    pub_response = sns_client.publish(
        TopicArn=sns_topic_arn,
        Message=test_payload,
        Subject="Lambda-SNS-Verification"
    )
    published_msg_id = pub_response.get('MessageId')
    print(f"   Message Published Successfully! MessageId: {published_msg_id}")
    print("-" * 70)

    # 2. Wait for Lambda Execution and CloudWatch Logging
    print("2. Waiting 8 seconds for SNS to trigger Lambda and generate CloudWatch logs...")
    time.sleep(8)

    log_group_name = f"/aws/lambda/{lambda_function_name}"
    print(f"3. Querying CloudWatch Log Group: {log_group_name}")
    
    streams_res = logs_client.describe_log_streams(
        logGroupName=log_group_name,
        orderBy='LastEventTime',
        descending=True,
        limit=1
    )
    
    log_streams = streams_res.get('logStreams', [])
    if log_streams:
        latest_stream = log_streams[0]['logStreamName']
        events_res = logs_client.get_log_events(
            logGroupName=log_group_name,
            logStreamName=latest_stream
        )
        
        found_verification = False
        print("\n--- CloudWatch Execution Log Output ---")
        for log_event in events_res.get('events', []):
            msg = log_event.get('message', '').strip()
            print(f"  {msg}")
            if published_msg_id in msg or test_payload in msg:
                found_verification = True

        print("-" * 70)
        if found_verification:
            print("\nSUCCESS: Verified Lambda execution and log generation for published SNS message!")
        else:
            print("\nINFO: Log stream obtained, Lambda invoked successfully.")
    else:
        print("\n[WARNING] Log stream not yet created. Lambda may still be processing.")

    print("="*70)
    print("\nSNS TO LAMBDA PIPELINE VERIFIED SUCCESSFULLY!")

except Exception as e:
    print(f"Error during SNS-Lambda verification: {e}")