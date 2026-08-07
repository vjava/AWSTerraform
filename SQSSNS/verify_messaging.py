import boto3
import json
import time

region = 'us-east-1'
sns_topic_arn = 'arn:aws:sns:us-east-1:654654589397:user-updates-topic-74dbf915'
sqs_queue_url = 'https://sqs.us-east-1.amazonaws.com/654654589397/app-processing-queue-74dbf915'

sns_client = boto3.client('sns', region_name=region)
sqs_client = boto3.client('sqs', region_name=region)

print("\n" + "="*70)
print("VERIFYING SNS TO SQS MESSAGING PIPELINE")
print("="*70)

try:
    # 1. Publish Message to SNS
    message_body = "Hello from Terraform SNS-SQS Pipeline Verification!"
    print(f"Publishing Message to SNS Topic: {sns_topic_arn}")
    pub_response = sns_client.publish(
        TopicArn=sns_topic_arn,
        Message=message_body,
        Subject="Automated Verification"
    )
    print(f"Message Published! MessageId: {pub_response.get('MessageId')}")
    print("-" * 70)

    # 2. Wait for propagation and Consume Message from SQS
    print("Waiting 3 seconds for SNS message to propagate to SQS...")
    time.sleep(3)

    print(f"Polling SQS Queue: {sqs_queue_url}")
    sqs_response = sqs_client.receive_message(
        QueueUrl=sqs_queue_url,
        MaxNumberOfMessages=1,
        WaitTimeSeconds=5
    )

    messages = sqs_response.get('Messages', [])
    if messages:
        msg = messages[0]
        receipt_handle = msg['ReceiptHandle']
        parsed_body = json.loads(msg['Body'])
        
        print("\nMessage Received Successfully in SQS Queue:")
        print(f"  - Message Body Payload: {parsed_body.get('Message')}")
        print(f"  - SNS Topic Source:    {parsed_body.get('TopicArn')}")
        print(f"  - Original Subject:    {parsed_body.get('Subject')}")

        # Delete consumed message
        sqs_client.delete_message(
            QueueUrl=sqs_queue_url,
            ReceiptHandle=receipt_handle
        )
        print("Message deleted from SQS queue post-verification.")
        print("="*70)
        print("\nSNS/SQS Messaging Pipeline Verification Completed Successfully!")
    else:
        print("\n[ERROR] No messages retrieved from SQS Queue. Check Subscription policies.")

except Exception as e:
    print(f"Error during messaging verification: {e}")