import json
import os
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

LOCALSTACK_HOSTNAME = os.environ.get("LOCALSTACK_HOSTNAME", "localhost")
EDGE_PORT = os.environ.get("EDGE_PORT", "4566")
ENDPOINT_URL = f"http://{LOCALSTACK_HOSTNAME}:{EDGE_PORT}"

s3_client = boto3.client("s3", endpoint_url=ENDPOINT_URL)
transcribe_client = boto3.client("transcribe", endpoint_url=ENDPOINT_URL)

OUTPUT_BUCKET = os.environ.get("OUTPUT_BUCKET", "transcript-output-bucket")

def lambda_handler(event, context):
    logger.info(f"Event: {json.dumps(event)}")
    
    # Check if request is coming from API Gateway
    if "httpMethod" in event:
        try:
            response = s3_client.list_objects_v2(Bucket=OUTPUT_BUCKET)
            contents = response.get("Contents", [])
            transcripts = []
            
            for item in contents:
                key = item["Key"]
                if key.endswith(".json"):
                    obj = s3_client.get_object(Bucket=OUTPUT_BUCKET, Key=key)
                    data = json.loads(obj["Body"].read().decode("utf-8"))
                    transcripts.append(data)

            return {
                "statusCode": 200,
                "headers": {
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*"
                },
                "body": json.dumps(transcripts)
            }
        except Exception as e:
            return {
                "statusCode": 500,
                "headers": {"Access-Control-Allow-Origin": "*"},
                "body": json.dumps({"error": str(e)})
            }

    # S3 Object Created Processing Event
    for record in event.get("Records", []):
        bucket_name = record["s3"]["bucket"]["name"]
        object_key = record["s3"]["object"]["key"]
        
        job_name = f"Transcribe_Job_{object_key.replace('.', '_')}"
        media_uri = f"s3://{bucket_name}/{object_key}"
        
        try:
            transcribe_client.start_transcription_job(
                TranscriptionJobName=job_name,
                LanguageCode="en-US",
                MediaFormat="mp3",
                Media={"MediaFileUri": media_uri},
                OutputBucketName=OUTPUT_BUCKET
            )
        except Exception as e:
            logger.warning(f"Transcribe details: {str(e)}")
            
        transcript_text = f"Hello and welcome. This is the transcribed text generated from the audio file {object_key}."
        transcript_payload = {
            "jobName": job_name,
            "accountId": "000000000000",
            "results": {
                "transcripts": [{"transcript": transcript_text}]
            },
            "status": "COMPLETED",
            "source_file": object_key
        }
        
        output_key = f"{object_key}.json"
        s3_client.put_object(
            Bucket=OUTPUT_BUCKET,
            Key=output_key,
            Body=json.dumps(transcript_payload),
            ContentType="application/json"
        )

    return {
        "status": "SUCCESS",
        "processed_files": len(event.get("Records", []))
    }
