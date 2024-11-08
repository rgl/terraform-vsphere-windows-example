# Usage (Ubuntu 22.04 host)

Install the [Windows 2022 VM template](https://github.com/rgl/windows-vagrant).

Install Terraform and govc (Ubuntu):

```bash
wget https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip
unzip terraform_1.9.8_linux_amd64.zip
sudo install terraform /usr/local/bin
rm terraform terraform_*_linux_amd64.zip
wget https://github.com/vmware/govmomi/releases/download/v0.45.1/govc_Linux_x86_64.tar.gz
tar xf govc_Linux_x86_64.tar.gz govc
sudo install govc /usr/local/bin/govc
rm govc govc_Linux_x86_64.tar.gz
```

Install Terraform and govc (Windows):

```bash
choco install -y --version 1.9.8 terraform
choco install -y --version 0.45.1 govc
```

Save your environment details as a script that sets the terraform variables from environment variables, e.g.:

```bash
cat >secrets.sh <<'EOF'
export TF_VAR_vm_hostname_prefix='example'
export TF_VAR_vm_count='1'
export TF_VAR_vm_cpu='2'
export TF_VAR_vm_memory='4' # [GiB]
export TF_VAR_vm_disk_os_size='60' # [GiB]
export TF_VAR_vm_disk_data_size='1' # [GiB]
export TF_VAR_vsphere_user='administrator@vsphere.local'
export TF_VAR_vsphere_password='password'
export TF_VAR_vsphere_server='vsphere.local'
export TF_VAR_vsphere_datacenter='Datacenter'
export TF_VAR_vsphere_compute_cluster='Cluster'
export TF_VAR_vsphere_datastore='Datastore'
export TF_VAR_vsphere_network='VM Network'
export TF_VAR_vsphere_folder='example'
export TF_VAR_vsphere_windows_template='vagrant-templates/windows-2022-amd64-vsphere'
export TF_VAR_winrm_username='vagrant'
# NB this value must meet the Windows password policy requirements.
#    see https://docs.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/password-must-meet-complexity-requirements
export TF_VAR_winrm_password='HeyH0Password'
export GOVC_INSECURE='1'
export GOVC_URL="https://$TF_VAR_vsphere_server/sdk"
export GOVC_USERNAME="$TF_VAR_vsphere_user"
export GOVC_PASSWORD="$TF_VAR_vsphere_password"
EOF
```

**NB** You could also add these variables definitions into the `terraform.tfvars` file, but I find the environment variables more versatile as they can also be used from other tools, like govc.

Launch this example:

```bash
source secrets.sh
# see https://github.com/vmware/govmomi/blob/master/govc/USAGE.md
govc version
govc about
govc datacenter.info # list datacenters
govc find # find all managed objects
terraform init
terraform plan -out=tfplan
time terraform apply tfplan
```

Login into the machine using SSH:

```bash
ssh-keygen -f ~/.ssh/known_hosts -R "$(terraform output --json ips | jq -r '.[0]')"
ssh "vagrant@$(terraform output --json ips | jq -r '.[0]')"
type C:\\cloudinit-config-example.ps1.log
exit # ssh
```

Login into the machine using PowerShell Remoting over SSH:

```bash
pwsh
Enter-PSSession -HostName "vagrant@$(terraform output --json ips | jq -r '.[0]')"
$PSVersionTable
whoami /all
Get-Content C:/cloudinit-config-example.ps1.log
exit # Enter-PSSession
exit # pwsh
```

Destroy the infrastructure:

```bash
time terraform destroy -auto-approve
```
