import sys
import boto3
from botocore.exceptions import ClientError

def print_log(section, check, result, success=True):
    status = "SUCCESS" if success else "FAILED"
    symbol = "✓" if success else "✗"
    print(f"[{symbol}] [{section}] {check:<45}: {result}")

def verify_s3_architecture(primary_bucket, lock_bucket, region="us-east-1"):
    s3 = boto3.client('s3', region_name=region)
    print("\n================================================================================")
    print(" AWS S3 ARCHITECTURE CLIENT AUDIT & VERIFICATION REPORT")
    print(f" Primary Bucket   : {primary_bucket}")
    print(f" Object Lock Bucket : {lock_bucket}")
    print("================================================================================\n")

    # 1. PUBLIC ACCESS BLOCK AUDIT
    print("=== 1. PUBLIC ACCESS BLOCK SAFEGUARDS ===")
    try:
        pba = s3.get_public_access_block(Bucket=primary_bucket)['PublicAccessBlockConfiguration']
        all_blocked = all([
            pba['BlockPublicAcls'],
            pba['IgnorePublicAcls'],
            pba['BlockPublicPolicy'],
            pba['RestrictPublicBuckets']
        ])
        print_log("PBA Check", "Enforced 4/4 Safeguards", f"BlockPublicAcls={pba['BlockPublicAcls']}, BlockPublicPolicy={pba['BlockPublicPolicy']}", success=all_blocked)
    except ClientError as e:
        print_log("PBA Check", "Fetch Status", f"Error: {e}", success=False)

    # 2. SERVER-SIDE ENCRYPTION AUDIT
    print("\n=== 2. SERVER-SIDE ENCRYPTION & BUCKET KEYS ===")
    try:
        enc = s3.get_bucket_encryption(Bucket=primary_bucket)
        rules = enc['ServerSideEncryptionConfiguration']['Rules']
        algo = rules[0]['ApplyServerSideEncryptionByDefault']['SSEAlgorithm']
        b_key = rules[0].get('BucketKeyEnabled', False)
        print_log("Encryption", "Default SSE Algorithm", f"Algorithm = {algo}", success=(algo == "AES256"))
        print_log("Encryption", "S3 Bucket Key Status", f"BucketKeyEnabled = {b_key}", success=b_key)
    except ClientError as e:
        print_log("Encryption", "Fetch Status", f"Error: {e}", success=False)

    # 3. VERSIONING CONTROL AUDIT
    print("\n=== 3. BUCKET VERSIONING STATUS ===")
    try:
        ver1 = s3.get_bucket_versioning(Bucket=primary_bucket).get('Status', 'Disabled')
        ver2 = s3.get_bucket_versioning(Bucket=lock_bucket).get('Status', 'Disabled')
        print_log("Versioning", "Primary Bucket Versioning", f"Status = {ver1}", success=(ver1 == 'Enabled'))
        print_log("Versioning", "Lock Bucket Versioning", f"Status = {ver2}", success=(ver2 == 'Enabled'))
    except ClientError as e:
        print_log("Versioning", "Fetch Status", f"Error: {e}", success=False)

    # 4. WORM / OBJECT LOCK RETENTION AUDIT
    print("\n=== 4. WORM COMPLIANCE & OBJECT LOCK RULES ===")
    try:
        lock_cfg = s3.get_object_lock_configuration(Bucket=lock_bucket)['ObjectLockConfiguration']
        enabled = lock_cfg.get('ObjectLockEnabled') == 'Enabled'
        mode = lock_cfg['Rule']['DefaultRetention']['Mode']
        days = lock_cfg['Rule']['DefaultRetention']['Days']
        print_log("Object Lock", "Lock Configuration State", f"Enabled = {enabled}", success=enabled)
        print_log("Object Lock", "Default WORM Mode", f"Mode = {mode} | Days = {days}", success=(mode == 'COMPLIANCE' and days == 7))
    except ClientError as e:
        print_log("Object Lock", "Fetch Status", f"Error: {e}", success=False)

    # 5. STORAGE LIFECYCLE MANAGEMENT AUDIT
    print("\n=== 5. STORAGE LIFECYCLE TIERING RULES ===")
    try:
        lifecycle = s3.get_bucket_lifecycle_configuration(Bucket=primary_bucket)['Rules']
        rule = lifecycle[0]
        rule_id = rule['ID']
        transition_days = rule['Transitions'][0]['Days']
        storage_class = rule['Transitions'][0]['StorageClass']
        noncurrent_exp = rule['NoncurrentVersionExpiration']['NoncurrentDays']
        print_log("Lifecycle", "Policy Rule Attached", f"RuleID = '{rule_id}'", success=True)
        print_log("Lifecycle", "Standard-IA Transition", f"Transitions after {transition_days} days to {storage_class}", success=(transition_days == 30 and storage_class == 'STANDARD_IA'))
        print_log("Lifecycle", "Noncurrent Version Purge", f"Purges old versions after {noncurrent_exp} days", success=(noncurrent_exp == 90))
    except ClientError as e:
        print_log("Lifecycle", "Fetch Status", f"Error: {e}", success=False)

    # 6. EVENTBRIDGE NOTIFICATION BUS AUDIT
    print("\n=== 6. EVENTBRIDGE EVENT BUS INTEGRATION ===")
    try:
        notif = s3.get_bucket_notification_configuration(Bucket=primary_bucket)
        eb_active = 'EventBridgeConfiguration' in notif
        print_log("EventBridge", "Event Bus Status", f"Active = {eb_active}", success=eb_active)
    except ClientError as e:
        print_log("EventBridge", "Fetch Status", f"Error: {e}", success=False)

    # 7. SECURITY POLICY & HTTPS ENFORCEMENT AUDIT
    print("\n=== 7. SECURITY BUCKET POLICY (TLS / HTTPS ENFORCE) ===")
    try:
        pol = s3.get_bucket_policy(Bucket=primary_bucket)['Policy']
        has_tls_clause = 'aws:SecureTransport' in pol and 'Deny' in pol
        print_log("Bucket Policy", "Non-HTTPS / TLS Deny Policy", f"SecureTransport Enforced = {has_tls_clause}", success=has_tls_clause)
    except ClientError as e:
        print_log("Bucket Policy", "Fetch Status", f"Error: {e}", success=False)

    print("\n================================================================================")
    print(" S3 ARCHITECTURAL AUDIT COMPLETE")
    print("================================================================================\n")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python verify_s3_architecture.py <primary_bucket_name> <lock_bucket_name>")
        print("Example: python verify_s3_architecture.py architect-master-bucket-8825 architect-lock-bucket-8825")
        sys.exit(1)

    primary = sys.argv[1]
    lock = sys.argv[2]
    verify_s3_architecture(primary, lock)