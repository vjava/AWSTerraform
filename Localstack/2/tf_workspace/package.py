import zipfile, os
work_dir = r'D:\Learning\Terraform\AWS\Localstack\2\tf_workspace'
for f in ['ValidateCustomer', 'FraudCheck', 'QueueProcessor']:
    py_p = os.path.join(work_dir, f + '.py')
    zip_p = os.path.join(work_dir, f + '.zip')
    with zipfile.ZipFile(zip_p, 'w', zipfile.ZIP_DEFLATED) as z:
        z.write(py_p, arcname=f + '.py')
