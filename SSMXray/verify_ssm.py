import boto3

region = 'us-east-1'
db_param_name = '/config/app/db_url_7c173cbb'
api_param_name = '/config/app/api_key_7c173cbb'

ssm_client = boto3.client('ssm', region_name=region)

print("\n" + "="*70)
print("AWS SSM PARAMETER STORE CONFIGURATION VERIFICATION")
print("="*70)

try:
    # 1. Verify Standard String Parameter
    print(f"1. Querying Standard Parameter: {db_param_name}...")
    p1 = ssm_client.get_parameter(Name=db_param_name)
    param1 = p1.get('Parameter', {})
    print(f"   Name:  {param1.get('Name')}")
    print(f"   Type:  {param1.get('Type')}")
    print(f"   Value: {param1.get('Value')}")
    print("   Standard Parameter Verified Successfully!")
    
    print("-" * 70)

    # 2. Verify SecureString Parameter with Decryption
    print(f"2. Querying SecureString Parameter (With Decryption): {api_param_name}...")
    p2 = ssm_client.get_parameter(Name=api_param_name, WithDecryption=True)
    param2 = p2.get('Parameter', {})
    print(f"   Name:      {param2.get('Name')}")
    print(f"   Type:      {param2.get('Type')}")
    print(f"   Decrypted: {param2.get('Value')}")
    print("   SecureString Parameter Verified Successfully!")

    print("="*70)
    print("\nAWS SSM PARAMETER STORE PIPELINE DEPLOYED & VERIFIED SUCCESSFULLY!")

except Exception as e:
    print(f"Verification Error: {e}")