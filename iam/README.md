```bash
sudo yum install -y yum-utils shadow-utils; sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo; sudo yum -y install terraform; \
alias k=kubectl; alias tf="terraform"; alias tfa="terraform apply --auto-approve"; alias tfd="terraform destroy --auto-approve"; alias tfm="terraform init; terraform fmt; terraform validate; terraform plan"
```
```bash
bucket_name=$(aws eks list-clusters --query clusters[0] --output text); \
primary_cluster=$(aws eks list-clusters --query clusters[0] --output text); \
recovery_cluster=$(aws eks list-clusters --query clusters[1] --output text); \
tfm -var $bucket_name-eks-velero-backups -var $primary_cluster -var $recovery_cluster
tfa -var $bucket_name-eks-velero-backups -var $primary_cluster -var $recovery_cluster
```
