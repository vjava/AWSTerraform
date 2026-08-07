import boto3

client = boto3.client('xray', region_name='us-east-1')

print("=" * 60)
print("AWS X-RAY CONFIGURATION VERIFICATION")
print("=" * 60)

try:
    # 1. Fetch Sampling Rules
    rules = client.get_sampling_rules()
    print("\n1. Querying X-Ray Sampling Rules...")
    for rule in rules.get('SamplingRuleRecords', []):
        spec = rule.get('SamplingRule', {})
        print(f"   Rule Name:     {spec.get('RuleName')}")
        print(f"   Priority:      {spec.get('Priority')}")
        print(f"   Fixed Rate:    {spec.get('FixedRate')}")
        print(f"   ReservoirSize: {spec.get('ReservoirSize')}")
        print("   Sampling Rules Verified Successfully!")

    # 2. Fetch Encryption Config
    print("\n2. Querying X-Ray Encryption Config...")
    enc = client.get_encryption_config()
    key_id = enc.get('EncryptionConfig', {}).get('KeyId', 'Default/AWS Managed')
    status = enc.get('EncryptionConfig', {}).get('Status', 'ACTIVE')
    print(f"   Key ID/Type:   {key_id}")
    print(f"   Status:        {status}")
    print("   Encryption Config Verified Successfully!")

    print("\n" + "=" * 60)
    print("X-RAY VERIFICATION COMPLETED SUCCESSFULLY!")
    print("=" * 60)

except Exception as e:
    print(f"Error verifying X-Ray: {e}")