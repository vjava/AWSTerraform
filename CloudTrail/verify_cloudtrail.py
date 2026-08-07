import boto3
import json
import time

trail_name = 'compliant-standard-trail-57e39f4e'
region = 'us-east-1'

ct_client = boto3.client('cloudtrail', region_name=region)

print(f"Verifying CloudTrail Configuration for: {trail_name}\n")

try:
    # 1. Get Trail Details
    trail_info = ct_client.describe_trails(trailNameList=[trail_name])['trailList'][0]
    print("="*70)
    print("CLOUDTRAIL CONFIGURATION STATUS")
    print("="*70)
    print(f"Trail Name:                  {trail_info.get('Name')}")
    print(f"S3 Bucket:                   {trail_info.get('S3BucketName')}")
    print(f"Log File Validation Enabled: {trail_info.get('LogFileValidationEnabled')}")
    print(f"Is Multi-Region Trail:       {trail_info.get('IsMultiRegionTrail')}")
    print("="*70)

    # 2. Check Logging Status
    status_info = ct_client.get_trail_status(Name=trail_name)
    print(f"\nIs Logging Active:           {status_info.get('IsLogging')}")
    print(f"Latest Delivery Time:        {status_info.get('LatestDeliveryTime', 'Pending initial delivery')}")

    # 3. Fetch Standard Management Events
    print("\nFetching Recent Standard Management Events (LookupEvents)...")
    events_response = ct_client.lookup_events(MaxResults=5)
    print("-" * 70)
    for event in events_response.get('Events', []):
        print(f"Event ID: {event.get('EventId')} | Name: {event.get('EventName')} | User: {event.get('Username', 'N/A')}")
    print("-" * 70)

    print("\nVerification Completed Successfully!")

except Exception as e:
    print(f"Error during verification: {e}")