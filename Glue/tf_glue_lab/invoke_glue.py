import boto3
import sys
import time

def invoke_and_monitor_glue_job(job_name, region_name="us-east-1"):
    print(f"\n[Python Client] Initializing AWS Glue client for region '{region_name}'...")
    client = boto3.client('glue', region_name=region_name)

    try:
        # 1. Trigger the Glue Job
        print(f"[Python Client] Starting execution for Glue Job: '{job_name}'...")
        response = client.start_job_run(JobName=job_name)
        job_run_id = response['JobRunId']
        print(f"[Python Client] Job Run Triggered Successfully. JobRunId: {job_run_id}")

        # 2. Poll for Execution Completion
        print("[Python Client] Polling job status...")
        while True:
            status_response = client.get_job_run(JobName=job_name, RunId=job_run_id)
            job_state = status_response['JobRun']['JobRunState']
            print(f"   -> Current State: {job_state}")

            if job_state in ['SUCCEEDED', 'FAILED', 'STOPPED', 'TIMEOUT']:
                break
            time.sleep(10)

        if job_state == 'SUCCEEDED':
            execution_time = status_response['JobRun'].get('ExecutionTime', 0)
            print(f"\n[SUCCESS] Glue Job completed in {execution_time} seconds!")
        else:
            error_message = status_response['JobRun'].get('ErrorMessage', 'Unknown error')
            print(f"\n[ERROR] Glue Job ended with state: {job_state}. Reason: {error_message}")
            sys.exit(1)

    except Exception as e:
        print(f"\n[Python Exception]: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python invoke_glue.py <glue_job_name> [region_name]")
        sys.exit(1)

    job_name_arg = sys.argv[1]
    region_arg = sys.argv[2] if len(sys.argv) > 2 else "us-east-1"
    invoke_and_monitor_glue_job(job_name_arg, region_arg)
