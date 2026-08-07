import boto3

region = 'us-east-1'
zone_id = 'Z07542641753VCLVX6DFF'
health_id = 'b3c7f469-6756-4d55-98a2-d88c8ced7441'

r53_client = boto3.client('route53', region_name=region)

print("\n" + "="*70)
print("AWS ROUTE 53 DNS ARCHITECTURE VERIFICATION")
print("="*70)

try:
    # 1. Verify Hosted Zone Details
    print(f"1. Querying Hosted Zone ID: {zone_id}...")
    zone_res = r53_client.get_hosted_zone(Id=zone_id)
    hz_info = zone_res.get('HostedZone', {})
    print(f"   Zone Name: {hz_info.get('Name')}")
    print(f"   Private Zone: {hz_info.get('Config', {}).get('PrivateZone')}")
    print(f"   Resource Record Set Count: {hz_info.get('ResourceRecordSetCount')}")
    print("   Hosted Zone Verified Successfully!")
    print("-" * 70)

    # 2. List DNS Resource Record Sets
    print(f"2. Querying Resource Record Sets for Zone: {zone_id}...")
    records_res = r53_client.list_resource_record_sets(HostedZoneId=zone_id)
    record_sets = records_res.get('ResourceRecordSets', [])
    
    print(f"   Found {len(record_sets)} DNS Record(s):")
    for r in record_sets:
        r_name = r.get('Name')
        r_type = r.get('Type')
        r_ttl = r.get('TTL', 'Alias/N/A')
        r_vals = [val.get('Value') for val in r.get('ResourceRecords', [])]
        print(f"   - Name: {r_name} | Type: {r_type} | TTL: {r_ttl} | Value: {r_vals}")

    print("-" * 70)

    # 3. Verify Health Check
    print(f"3. Querying Route 53 Health Check ID: {health_id}...")
    hc_res = r53_client.get_health_check(HealthCheckId=health_id)
    hc_config = hc_res.get('HealthCheck', {}).get('HealthCheckConfig', {})
    print(f"   Fully Qualified Domain Name: {hc_config.get('FullyQualifiedDomainName')}")
    print(f"   Port: {hc_config.get('Port')}")
    print(f"   Type: {hc_config.get('Type')}")
    print("   Route 53 Health Check Verified Successfully!")

    print("="*70)
    print("\nROUTE 53 PIPELINE DEPLOYED & VERIFIED SUCCESSFULLY!")

except Exception as e:
    print(f"Verification Error: {e}")
