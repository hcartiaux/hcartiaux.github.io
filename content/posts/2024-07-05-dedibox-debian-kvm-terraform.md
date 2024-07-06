---
title: "Bootstrapping VMs on a virtualization server with Debian, KVM/libvirt using Terraform and cloud-init (Part 2/2)"
date: 2024-07-05
tags: [linux, sysadmin, network, terraform, homelab]
toc: true
---

[In the first part](/posts/2024-03-11-dedibox-debian-kvm-libvirt-ipv6/), we have set-up a cheap virtualization server on a [dedibox](https://www.scaleway.com/en/dedibox/).
My next objective was to use my cheap server to spawn VMs, instead of buying expensive VPS or cloud instances.
For this matter, I use Terraform, and I've published [my Terraform configuration on github](https://github.com/hcartiaux/terraform).

<!--more-->

## Terraform workflow

The typical workflow fits in 4 commands:

* Prepare the working directory: `terraform init`
* Show changes to the infrastructure required by the current configuration: `terraform plan`
* Create or modify the infrastructure: `terraform apply`
* Destroy all the infrastructure: `terraform destroy`

## Cloud-init

[Cloud-init](https://cloud-init.io/) is a tool developed by Canonical to configure instances on boot, with support to many cloud platforms and operating systems. It permits to initialize cloud instance and provide a base configuration applied at boot time. The documentation is available here:

* [https://cloudinit.readthedocs.io/](https://cloudinit.readthedocs.io/en/latest/)

System images with cloud-init pre-installed are usually named "cloud images" and distributed for many Linux distributions alongside the installation ISOs.

Cloud-init supports a "NoCloud" mode, where the configuration is passed to the system in an ISO file attached to the VM.
This is the mode that we will use below.

## Terraform provider for libvirt

Terraform supports many different infrastructures, especially cloud infrastructure such as Azure or Amazon AWS.
But I don't want to pay for a public cloud, I want to use my own virtualization server as backend.

I've found that this unofficial Terraform provider for libvirt is actually reliable: [https://github.com/dmacvicar/terraform-provider-libvirt](https://github.com/dmacvicar/terraform-provider-libvirt)

Some examples are given [in the repository](https://github.com/dmacvicar/terraform-provider-libvirt/tree/main/examples/v0.13).

I will briefly explain [this example](https://github.com/dmacvicar/terraform-provider-libvirt/blob/main/examples/v0.13/resize_base/main.tf), which will spawn an Ubuntu VM with a custom disk size.

1. Specify the terraform provider source

```hcl
terraform {
 required_version = ">= 0.13"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.6.2"
    }
  }
}
```

2. Configure the libvirt provider, specify the URI of your libvirt daemon, it can be local like in this example or accessed remotely via SSH (`qemu+ssh://<ssh host>/system`)

```hcl
provider "libvirt" {
  uri = "qemu:///system"
}
```

3. Specify the source of the system image, and the system disk size, using resources of type `libvirt_volume`

```hcl
resource "libvirt_volume" "os_image_ubuntu" {
  name   = "os_image_ubuntu"
  pool   = "default"
  source = "https://cloud-images.ubuntu.com/releases/xenial/release/ubuntu-16.04-server-cloudimg-amd64-disk1.img"
}

resource "libvirt_volume" "disk_ubuntu_resized" {
  name           = "disk"
  base_volume_id = libvirt_volume.os_image_ubuntu.id
  pool           = "default"
  size           = 5361393152
}
```

4. Specify your cloud-init configuration in a resource of type `libvirt_cloudinit_disk`.
The provided configuration will be transformed into an iso file and attached to the virtual machine on boot.

```hcl
# Use CloudInit to add our ssh-key to the instance
resource "libvirt_cloudinit_disk" "cloudinit_ubuntu_resized" {
  name = "cloudinit_ubuntu_resized.iso"
  pool = "default"

  user_data = <<EOF
#cloud-config
disable_root: 0
ssh_pwauth: 1
users:
  - name: root
    ssh-authorized-keys:
      - ${file("id_rsa.pub")}
growpart:
  mode: auto
  devices: ['/']
EOF
}
```

5. Define a virtual machine (called "domain" in libvirt)

```hcl
resource "libvirt_domain" "domain_ubuntu_resized" {
  name = "doman_ubuntu_resized"
  memory = "512"
  vcpu = 1
  cloudinit = libvirt_cloudinit_disk.cloudinit_ubuntu_resized.id
[...]
  disk {
    volume_id = libvirt_volume.disk_ubuntu_resized.id
  }
[...]
}
```

## My Terraform configuration

[My terraform configuration is public on github](https://github.com/hcartiaux/terraform).

This terraform configuration permits to manage a single libvirt server at a time.
The cool feature is that all the configuration is provided in one `tfvars` file using the standard terraform syntax (HCL), and converted seamlessly to cloud-init.

The configuration layout is the following:

* `versions.tf` - terraform and libvirt provider version requirement
* `provider.tf` - libvirt provider configuration
* `vms/` - specific module to define one virtual machine based on the description provided in input
* `main.tf` - entry point, iterate other the variable vms_list to define virtual machines using the module `vms`
* `variables.tf` - input variables definitions
* `terraform.tfvars` - input variables, processed in `main.tf` - **this is the main configuration file**

One server configuration is stored per `tfvars` file. In my case, I have only one server, and its configuration is stored in the form of variable definitions, the file `terraform.tfvars` which is loaded by default.

I could manage several servers by creating more `tfvars` and selecting them on the command line (`terraform apply -var-file="new_libvirt_server.tfvars"`).

I will only explain in detail my `terraform.tfvars`, since it's the only file that has to be regularly updated.

1. This is the libvirt server configuration

```hcl
server_uri = "qemu+ssh://hcartiaux@srv.nbsdn.fr.eu.org:443/system"
pool_name  = "terraform"
pool_path  = "/var/lib/libvirt/terraform"
```

2. Since all VMs share the same network, I define the gateways and nameservers in common

```hcl
network_defaults = {
  gateway4    = "192.168.0.1"
  gateway6    = "2001:bc8:3feb:100::2"
  nameservers = ["2001:bc8:3feb:100::2"]
}
```

3. I specify default user settings for all VMs. The root account is locked for all VMs. `users_default` is a [map](https://spacelift.io/blog/terraform-map-variable) of user objects, so it could be used to define several users.

```hcl
users_defaults = {
  "root" = {
    hashed_passwd = "!"
    lock_passwd   = true
  }
}
```

4. I define the map `vms_list`, which is actually the list of VMs.

```hcl
vms_list = {
[...]
  "tf-debian" = {
    bridge_name     = "vmbr0"
    vm_memory       = 384
    vm_vcpu         = 1
    vm_disk_size    = 100
    cloud_image_url = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
    network_interfaces = {
      ens3 = {
        addresses = [
          "192.168.0.9/16",
          "2001:bc8:3feb:100::9/64",
        ]
      }
    }
    system = {
      hostname = "tf-debian"
      packages = ["wget"]
    }
    users = {
      "sysadmin" = {
        shell               = "/bin/bash"
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        hashed_passwd       = "!"
        lock_passwd         = true
        ssh_authorized_keys = ["ssh-ed25519 ......................"]
      }
    }
  }
[...]
}
```

After running `terraform apply`, the VM will be quickly reachable via SSH on the network.

## Spawning an OpenBSD instance

Lucky you, OpenBSD does not provide cloud images, but you can use mine !

I've created the github project [openbsd-cloud-image](https://github.com/hcartiaux/openbsd-cloud-image), in order to generate cloud-init enabled images of OpenBSD.

The project provides:

* a [bash script `build_openbsd_qcow2.sh`](https://github.com/hcartiaux/openbsd-cloud-image/blob/main/build_openbsd_qcow2.sh), which starts an unattended PXE installation of OpenBSD and produce a qcow2 system image.
* a [CI/CD pipeline](https://github.com/hcartiaux/openbsd-cloud-image/actions/) to generate new system images, test them briefly and release them
* the [qcow2 images](https://github.com/hcartiaux/openbsd-cloud-image/releases/latest), which I use directly in my Terraform configuration.

In my configuration, I can spawn an OpenBSD instance using this configuration:

```hcl
vms_list = {
[...]
  "tf-openbsd" = {
    bridge_name     = "vmbr0"
    vm_memory       = 384
    vm_vcpu         = 1
    vm_disk_size    = 100
    cloud_image_url = "https://github.com/hcartiaux/openbsd-cloud-image/releases/download/v7.5_2024-05-13-15-25/openbsd-min.qcow2"
    network_interfaces = {
      vio0 = {
        addresses = [
          "192.168.0.10/16",
          "2001:bc8:3feb:100::10/64",
        ]
      }
    }
    system = {
      hostname = "tf-openbsd"
      packages = ["wget", "bash", "vim--no_x11"]
    }
    users = {
      "sysadmin" = {
        shell               = "/usr/local/bin/bash"
        doas                = "permit nopass hcartiaux as root"
        hashed_passwd       = "!"
        lock_passwd         = true
        ssh_authorized_keys = ["ssh-ed25519 ......................"]
      }
    }
  }
[...]
}
```

## That's all folks

This is how I set-up my "homelab" experiments on a cheap dedicated server. 
Once my VMs are booted and reachable, I customize them using [my ansible configuration](https://github.com/hcartiaux/ansible).
