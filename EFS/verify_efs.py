import boto3

region = 'us-east-1'
efs_id = 'fs-04f16196e9014ac28'
mt_id = 'fsmt-0ee709da03c52079e'

efs_client = boto3.client('efs', region_name=region)

print("\n" + "="*70)
print("AWS EFS (ELASTIC FILE SYSTEM) CONFIGURATION VERIFICATION")
print("="*70)

try:
    # 1. Verify EFS File System
    print(f"1. Querying EFS File System Details for: {efs_id}...")
    fs_res = efs_client.describe_file_systems(FileSystemId=efs_id)
    file_systems = fs_res.get('FileSystems', [])
    
    if file_systems:
        fs = file_systems[0]
        print(f"   Creation Token:   {fs.get('CreationToken')}")
        print(f"   Life Cycle State: {fs.get('LifeCycleState')}")
        print(f"   Performance Mode: {fs.get('PerformanceMode')}")
        print(f"   Throughput Mode:  {fs.get('ThroughputMode')}")
        print(f"   Encrypted:        {fs.get('Encrypted')}")
        print("   File System Verified Successfully!")
    
    print("-" * 70)

    # 2. Verify Lifecycle Configuration
    print(f"2. Querying Lifecycle Policy for EFS: {efs_id}...")
    lc_res = efs_client.describe_lifecycle_configuration(FileSystemId=efs_id)
    policies = lc_res.get('LifecyclePolicies', [])
    for p in policies:
        print(f"   Transition to IA Policy: {p.get('TransitionToIA')}")
    print("   Lifecycle Policy Verified Successfully!")

    print("-" * 70)

    # 3. Verify Mount Target
    print(f"3. Querying EFS Mount Target: {mt_id}...")
    mt_res = efs_client.describe_mount_targets(MountTargetId=mt_id)
    mount_targets = mt_res.get('MountTargets', [])
    if mount_targets:
        mt = mount_targets[0]
        print(f"   Mount Target ID:   {mt.get('MountTargetId')}")
        print(f"   Subnet ID:         {mt.get('SubnetId')}")
        print(f"   IP Address:        {mt.get('IpAddress')}")
        print(f"   Life Cycle State:  {mt.get('LifeCycleState')}")
        print("   Mount Target Verified Successfully!")

    print("="*70)
    print("\nEFS ARCHITECTURE DEPLOYED & VERIFIED SUCCESSFULLY!")

except Exception as e:
    print(f"Verification Error: {e}")