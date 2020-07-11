terraform {
  required_version = ">= 0.12"
  required_providers {
    template = "~> 2.1"
    vsphere = "~> 1.21"
  }
}

variable "vsphere_user" {
  default = "administrator@vsphere.local"
}

variable "vsphere_password" {
  default = "password"
}

variable "vsphere_server" {
  default = "vsphere.local"
}

variable "vsphere_datacenter" {
  default = "Datacenter"
}

variable "vsphere_compute_cluster" {
  default = "Cluster"
}

variable "vsphere_network" {
  default = "VM Network"
}

variable "vsphere_datastore" {
  default = "Datastore"
}

variable "vsphere_windows_template" {
  default = "vagrant-templates/windows-2019-amd64-vsphere"
}

variable "winrm_username" {
  default = "vagrant"
}

variable "winrm_password" {
  # set the administrator password.
  # NB the administrator password will be reset to this value by the cloudbase-init SetUserPasswordPlugin plugin.
  # NB this value must meet the Windows password policy requirements.
  #    see https://docs.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/password-must-meet-complexity-requirements
  default = "HeyH0Password"
}

variable "prefix" {
  default = "terraform_windows_example"
}

provider "vsphere" {
  user = var.vsphere_user
  password = var.vsphere_password
  vsphere_server = var.vsphere_server
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "datacenter" {
  name = var.vsphere_datacenter
}

data "vsphere_compute_cluster" "compute_cluster" {
  name = var.vsphere_compute_cluster
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_datastore" "datastore" {
  name = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "network" {
  name = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_virtual_machine" "windows_template" {
  name = var.vsphere_windows_template
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

# a multipart cloudbase-init cloud-config.
# see https://github.com/cloudbase/cloudbase-init
# see https://cloudbase-init.readthedocs.io/en/latest/userdata.html#userdata
# see https://www.terraform.io/docs/providers/template/d/cloudinit_config.html
# see https://www.terraform.io/docs/configuration/expressions.html#string-literals
data "template_cloudinit_config" "example" {
  part {
    content_type = "text/cloud-config"
    content = <<-EOF
      #cloud-config
      hostname: example
      timezone: Asia/Tbilisi
      EOF
  }
  part {
    filename = "example.ps1"
    content_type = "text/x-shellscript"
    content = <<-EOF
      #ps1_sysnative
      Start-Transcript -Append "C:\cloudinit-config-example.ps1.log"
      function Write-Title($title) {
        Write-Output "`n#`n# $title`n#"
      }
      Write-Title "whoami"
      whoami /all
      Write-Title "Windows version"
      cmd /c ver
      Write-Title "Environment Variables"
      dir env:
      Write-Title "TimeZone"
      Get-TimeZone
      EOF
  }
}

# see https://www.terraform.io/docs/providers/vsphere/r/virtual_machine.html
resource "vsphere_virtual_machine" "example" {
  name = var.prefix
  guest_id = data.vsphere_virtual_machine.windows_template.guest_id
  num_cpus = 2
  num_cores_per_socket = 2
  memory = 1024
  resource_pool_id = data.vsphere_compute_cluster.compute_cluster.resource_pool_id
  datastore_id = data.vsphere_datastore.datastore.id
  scsi_type = data.vsphere_virtual_machine.windows_template.scsi_type
  disk {
    unit_number = 0
    label = "os"
    # NB we add 2 [GiB] to test the C: drive expansion.
    size = data.vsphere_virtual_machine.windows_template.disks.0.size + 2
    eagerly_scrub = data.vsphere_virtual_machine.windows_template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.windows_template.disks.0.thin_provisioned
  }
  disk {
    unit_number = 1
    label = "data"
    size = 6 # [GiB]
    eagerly_scrub = data.vsphere_virtual_machine.windows_template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.windows_template.disks.0.thin_provisioned
  }
  network_interface {
    network_id = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.windows_template.network_interface_types.0
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.windows_template.id
  }
  # NB this extra_config data ends-up inside the VM .vmx file and will be
  #    exposed by cloudbase-init as a cloud-init datasource.
  extra_config = {
    "guestinfo.metadata" = base64gzip(jsonencode({
      "admin-username": var.winrm_username,
      "admin-password": var.winrm_password,
      "public-keys-data": trimspace(file("~/.ssh/id_rsa.pub")),
    })),
    "guestinfo.metadata.encoding" = "gzip+base64",
    "guestinfo.userdata" = data.template_cloudinit_config.example.rendered,
    "guestinfo.userdata.encoding" = "gzip+base64"
  }
  provisioner "remote-exec" {
    inline = [
      <<-EOF
      whoami /all
      ver
      PowerShell "Get-Disk | Select-Object Number,PartitionStyle,Size | Sort-Object Number"
      PowerShell "Get-Volume | Sort-Object DriveLetter,FriendlyName"
      EOF
    ]
    connection {
      type = "winrm"
      user = var.winrm_username
      password = var.winrm_password
      host = self.default_ip_address
      timeout = "1h"
    }
  }
}

output "ip" {
  value = vsphere_virtual_machine.example.default_ip_address
}
