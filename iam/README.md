```bash
alias k=kubectl; alias tf="terraform"; alias tfa="terraform apply --auto-approve"; alias tfd="terraform destroy --auto-approve"; alias tfm="terraform init; terraform fmt; terraform validate; terraform plan"
sudo yum install -y yum-utils shadow-utils; sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo; sudo yum -y install terraform;
```
```bash
bucket_name=$(aws eks list-clusters --query clusters[0] --output text);
primary_cluster=$(aws eks list-clusters --query clusters[0] --output text);
recovery_cluster=$(aws eks list-clusters --query clusters[1] --output text);
region_code=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]');
account_id=$(aws sts get-caller-identity --query Account --output text)
tfm -var account_id=$account_id -var region=$region_code -var bucket_name=$bucket_name-eks-velero-backups -var primary_cluster=$primary_cluster -var recovery_cluster=$recovery_cluster
tfa -var account_id=$account_id -var region=$region_code -var bucket_name=$bucket_name-eks-velero-backups -var primary_cluster=$primary_cluster -var recovery_cluster=$recovery_cluster
```
```bash
PRIMARY_CLUSTER=$(aws eks list-clusters --query clusters[0] --output text); \
RECOVERY_CLUSTER=$(aws eks list-clusters --query clusters[1] --output text); \
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
    --cluster=$PRIMARY_CLUSTER \
    --name=velero-server \
    --namespace=velero \
    --role-name=eks-velero-backup \
    --role-only \
    --attach-policy-arn=arn:aws:iam::$ACCOUNT:policy/VeleroAccessPolicy \
    --approve

eksctl create iamserviceaccount \
    --cluster=$RECOVERY_CLUSTER \
    --name=velero-server \
    --namespace=velero \
    --role-name=eks-velero-recovery \
    --role-only \
    --attach-policy-arn=arn:aws:iam::$ACCOUNT:policy/VeleroAccessPolicy \
    --approve
```
```bash
PRIMARY_CLUSTER=$(aws eks list-clusters --query clusters[0] --output text); \
RECOVERY_CLUSTER=$(aws eks list-clusters --query clusters[1] --output text); \
REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]'); \
PRIMARY_CONTEXT=primary; \
RECOVERY_CONTEXT=recovery; \
aws eks --region $REGION update-kubeconfig --name $PRIMARY_CLUSTER --alias $PRIMARY_CONTEXT; \
aws eks --region $REGION update-kubeconfig --name $RECOVERY_CLUSTER --alias $RECOVERY_CONTEXT
```
