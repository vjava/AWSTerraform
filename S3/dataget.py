import sys
import time
import boto3
from cryptography.fernet import Fernet

# Configuration
REGION = "us-east-1"
OBJECT_KEY = "secure_data.csv"

# Sample data in CSV (SC) format
CSV_DATA_V1 = """ID,Name,Role,Salary
101,Alice,Cloud Architect,120000
102,Bob,DevOps Engineer,95000
103,Charlie,Security Specialist,110000"""

CSV_DATA_V2 = """ID,Name,Role,Salary
101,Alice,Lead Cloud Architect,135000
102,Bob,Senior DevOps Engineer,110000
103,Charlie,Security Director,130000
104,Diana,SRE Engineer,105000"""


def get_latest_hardened_bucket(s3_client):
    """Finds the most recently created hardened-lab-bucket in S3."""
    response = s3_client.list_buckets()
    buckets = [
        b["Name"]
        for b in response.get("Buckets", [])
        if b["Name"].startswith("hardened-lab-bucket-")
        or b["Name"].startswith("lab-app-data-")
    ]
    if not buckets:
        print("Error: No lab S3 buckets found. Run main2.ps1 first.")
        sys.exit(1)
    # Return the latest created bucket
    return sorted(buckets)[-1]


def main():
    s3 = boto3.client("s3", region_name=REGION)
    bucket_name = get_latest_hardened_bucket(s3)

    print(f"=== Target S3 Bucket: {bucket_name} ===")

    # 1. Generate local encryption key (Fernet / AES-128 in CBC mode)
    encryption_key = Fernet.generate_key()
    cipher = Fernet(encryption_key)
    print("1. Encryption key generated locally.")

    # 2. Encrypt Initial CSV Data
    encrypted_bytes_v1 = cipher.encrypt(CSV_DATA_V1.encode("utf-8"))

    # 3. Upload Version 1 (Client-side Encrypted + SSE-S3 AES256)
    print(f"2. Uploading Encrypted Version 1 of '{OBJECT_KEY}'...")
    res1 = s3.put_object(
        Bucket=bucket_name,
        Key=OBJECT_KEY,
        Body=encrypted_bytes_v1,
        ServerSideEncryption="AES256",
        ContentType="text/csv",
    )
    v1_id = res1.get("VersionId")
    print(f"   Upload successful! Version ID 1: {v1_id}\n")

    # 4. Read, Decrypt, and Display Version 1
    print("3. Fetching and decrypting Version 1 from S3...")
    obj1 = s3.get_object(Bucket=bucket_name, Key=OBJECT_KEY)
    decrypted_v1 = cipher.decrypt(obj1["Body"].read()).decode("utf-8")
    print("--- DISPLAYING DECRYPTED V1 CSV DATA ---")
    print(decrypted_v1)
    print("---------------------------------------\n")

    # 5. Delete Object to create a Delete Marker
    print("4. Deleting file from S3 to test versioning Delete Marker...")
    del_res = s3.delete_object(Bucket=bucket_name, Key=OBJECT_KEY)
    del_marker_id = del_res.get("VersionId")
    print(f"   Delete Marker created! Version ID: {del_marker_id}\n")

    # 6. Encrypt and Re-create File with Version 2 Data
    encrypted_bytes_v2 = cipher.encrypt(CSV_DATA_V2.encode("utf-8"))
    print(f"5. Re-creating '{OBJECT_KEY}' with Version 2 Data...")
    res2 = s3.put_object(
        Bucket=bucket_name,
        Key=OBJECT_KEY,
        Body=encrypted_bytes_v2,
        ServerSideEncryption="AES256",
        ContentType="text/csv",
    )
    v2_id = res2.get("VersionId")
    print(f"   Upload successful! Version ID 2: {v2_id}\n")

    # 7. Read, Decrypt, and Display Latest Data (Version 2)
    print("6. Fetching and decrypting current active version (V2)...")
    obj2 = s3.get_object(Bucket=bucket_name, Key=OBJECT_KEY)
    decrypted_v2 = cipher.decrypt(obj2["Body"].read()).decode("utf-8")
    print("--- DISPLAYING DECRYPTED V2 CSV DATA ---")
    print(decrypted_v2)
    print("---------------------------------------\n")

    # 8. Retrieve Historical Version 1 (Before Delete Marker)
    if v1_id:
        print(f"7. Testing recovery: Fetching historical Version 1 ({v1_id})...")
        obj_hist = s3.get_object(
            Bucket=bucket_name, Key=OBJECT_KEY, VersionId=v1_id
        )
        decrypted_hist = cipher.decrypt(obj_hist["Body"].read()).decode("utf-8")
        print("--- DISPLAYING HISTORICAL DECRYPTED V1 DATA ---")
        print(decrypted_hist)
        print("-----------------------------------------------\n")

    # 9. List All Version Objects stored in S3
    print("=== SUMMARY OF ALL S3 VERSIONS STORED ===")
    versions = s3.list_object_versions(Bucket=bucket_name, Prefix=OBJECT_KEY)

    print("Active & Historical Versions:")
    for v in versions.get("Versions", []):
        print(
            f"  - VersionId: {v['VersionId']} | IsLatest: {v['IsLatest']} | Size: {v['Size']} bytes"
        )

    print("\nDelete Markers:")
    for dm in versions.get("DeleteMarkers", []):
        print(
            f"  - VersionId: {dm['VersionId']} | IsLatest: {dm['IsLatest']} (Delete Marker)"
        )


if __name__ == "__main__":
    main()