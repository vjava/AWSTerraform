import sys
import boto3

LOCALSTACK_ENDPOINT = "http://localhost:4566"
MEDIA_BUCKET = "media-audio-bucket"

def upload_sample_audio(filename):
    s3_client = boto3.client(
        "s3",
        endpoint_url=LOCALSTACK_ENDPOINT,
        aws_access_key_id="test",
        aws_secret_access_key="test",
        region_name="us-east-1"
    )
    mock_audio_content = b"MOCK_AUDIO_DATA_FOR_TRANSCRIBE"
    s3_client.put_object(
        Bucket=MEDIA_BUCKET,
        Key=filename,
        Body=mock_audio_content,
        ContentType="audio/mp3"
    )
    print(f"[CLIENT] Uploaded sample audio '{filename}' to S3 bucket '{MEDIA_BUCKET}'.")

if __name__ == "__main__":
    file_name = sys.argv[1] if len(sys.argv) > 1 else "sample_speech.mp3"
    upload_sample_audio(file_name)
