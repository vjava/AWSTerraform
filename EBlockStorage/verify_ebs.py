import boto3

region = 'us-east-1'
volume_id = 'vol-0a1d3935f6a767170'
snapshot_id = 'snap-0ab09b5c425ef8c75'

ec2_client = boto3.client('ec2', region_name=region)

print("\n" + "="*70)
print("AWS EBS (ELASTIC BLOCK STORAGE) CONFIGURATION VERIFICATION")
print("="*70)

try:
    # 1. Verify EBS Volume
    print(f"1. Querying EBS Volume Details for: {volume_id}...")
    vol_res = ec2_client.describe_volumes(VolumeIds=[volume_id])
    volumes = vol_res.get('Volumes', [])
    
    if volumes:
        vol = volumes[0]
        print(f"   Volume ID:         {vol.get('VolumeId')}")
        print(f"   Size (GB):          {vol.get('Size')} GB")
        print(f"   Volume Type:        {vol.get('VolumeType')}")
        print(f"   Availability Zone:  {vol.get('AvailabilityZone')}")
        print(f"   State:              {vol.get('State')}")
        print(f"   Encrypted:          {vol.get('Encrypted')}")
        print("   EBS Volume Verified Successfully!")
    
    print("-" * 70)

    # 2. Verify EBS Snapshot
    print(f"2. Querying EBS Snapshot Details for: {snapshot_id}...")
    snap_res = ec2_client.describe_snapshots(SnapshotIds=[snapshot_id])
    snapshots = snap_res.get('Snapshots', [])
    if snapshots:
        snap = snapshots[0]
        print(f"   Snapshot ID:       {snap.get('SnapshotId')}")
        print(f"   Source Volume ID:   {snap.get('VolumeId')}")
        print(f"   State:              {snap.get('State')}")
        print(f"   Progress:           {snap.get('Progress')}")
        print(f"   Encrypted:          {snap.get('Encrypted')}")
        print("   EBS Snapshot Verified Successfully!")

    print("="*70)
    print("\nEBS ARCHITECTURE DEPLOYED & VERIFIED SUCCESSFULLY!")

except Exception as e:
    print(f"Verification Error: {e}")