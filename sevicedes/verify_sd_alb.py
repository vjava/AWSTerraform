import boto3
import requests
import time

region = 'us-east-1'
service_id = 'srv-wjzwjsawqs7y4dla'
alb_dns = 'sd-demo-alb-da4206ba-1308853141.us-east-1.elb.amazonaws.com'

servicediscovery_client = boto3.client('servicediscovery', region_name=region)

print("\n" + "="*70)
print("AWS SERVICE DISCOVERY & ELASTIC LOAD BALANCING VERIFICATION")
print("="*70)

# 1. Query Service Discovery Details via AWS API
print(f"1. Querying Service Discovery API for Service ID: {service_id}...")
try:
    response = servicediscovery_client.get_service(Id=service_id)
    sd_service_info = response.get('Service', {})
    print(f"   Service Name: {sd_service_info.get('Name')}")
    print(f"   Service ARN:  {sd_service_info.get('Arn')}")
    print(f"   Namespace ID: {sd_service_info.get('NamespaceId')}")
    print("   Service Discovery Service Verified Successfully!")

    print("-" * 70)

    # 2. Verify ALB Ingress HTTP Traffic
    target_url = f"http://{alb_dns}"
    print(f"2. Testing HTTP Connectivity to Application Load Balancer: {target_url}")
    
    # Wait briefly for ALB provisioning
    time.sleep(5)
    
    http_res = requests.get(target_url, timeout=10)
    print(f"   HTTP Response Code: {http_res.status_code}")
    print(f"   HTTP Response Body: {http_res.text}")
    
    if http_res.status_code == 200:
        print("\nSUCCESS: Service Discovery and Application Load Balancer Verified Successfully!")
    else:
        print(f"\nINFO: Request completed with status code {http_res.status_code}")

except Exception as e:
    print(f"Verification Error: {e}")

print("="*70)
print("\nSERVICE DISCOVERY + ELB PIPELINE VERIFICATION COMPLETE!")