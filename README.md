# learn-velero-eks-backup
how to backup aws eks cluster with velero
1. Using s3 to export backup configmaps, secrets and pvc
```bash
# Replace <BUCKETNAME> and <REGION> with your own values below.
BUCKET=<BUCKETNAME>
REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
aws s3 mb s3://$BUCKET --region $REGION
cat > velero_policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots",
                "ec2:CreateTags",
                "ec2:CreateVolume",
                "ec2:CreateSnapshot",
                "ec2:DeleteSnapshot"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:PutObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET}"
            ]
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name VeleroAccessPolicy \
    --policy-document file://velero_policy.json
```
Resource - https://bluexp.netapp.com/blog/cbs-aws-blg-eks-back-up-how-to-back-up-and-restore-eks-with-velero

https://aws.amazon.com/blogs/containers/backup-and-restore-your-amazon-eks-cluster-resources-using-velero/
