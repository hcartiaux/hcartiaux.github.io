---
title: "Dedibox - set-up a virtualization server with Debian, KVM/libvirt and IPv6"
date: 2024-03-11T23:28:00+02:00
draft: false
---

The objective is to set-up a virtualization server on a [dedibox](https://www.scaleway.com/en/dedibox/) server with IPv6 support.

In IPv4, the customer will typically buy "failover IPs" individually, register the virtual machines mac addresses on the console, and bridge the host server physical network interface.
If the server emits packets from unregistered mac addresses, the server will be flagged and put offline (as a security measure).

It is not possible to register additional mac addresses without buying the "failover IPs", so we will route the IPv6 traffic on the host server instead of bridging the physical network interface.

0. Buy a "Dedibox" server on online.net

1. Online allocates a /48 to each customer, we will split it and create a /56 in the console.

![Dedibox console IPv6](dedibox_network_config.png)

2. Install convenient packages on the server

```bash
apt install vim tmux bridge-utils tcpdump dnsutils htop sudo
```

3. Enable IPv6

```bash
echo ipv6 > /etc/modules-load.d/modules.conf
echo options ipv6 disable=0 > /etc/modprobe.d/local.conf
```

4. Configure DHCPv6 to request your IPv6 block, create a file `/etc/dhcp/dhclient6.conf`. Replace the client-id value by the DUID given in the console.

```
interface "enp1s0" {
send dhcp6.client-id xx:xx:xx:xx:xx:xx:xx:xx:xx:xx;
request;
}
```

5. In `/etc/network/interfaces`, configure the physical network interface (`enp1s0`) for IPv4 (dhcp) and IPv6.

```
# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug enp1s0
iface enp1s0 inet dhcp

# Bridge setup
iface enp1s0 inet6 static
  address 2001:xxx:xxx:100::1
  netmask 64
  accept_ra 2
  pre-up dhclient -cf /etc/dhcp/dhclient6.conf -pf /run/dhclient6.enp1s0.pid -v -nw -6 -P enp1s0
  pre-down dhclient -x -pf /run/dhclient6.enp1s0.pid
```

6. Configure a network bridge for the virtual machines.

```
auto vmbr0
iface vmbr0 inet6 static
  address 2001:xxx:xxx:100::2
  netmask 64
  dad-attempts 0
  bridge_ports none
  bridge_stp off
  bridge_fd 0
  post-up /sbin/ip -f inet6 neigh add proxy 2001:xxx:xxx:100::2 dev vmbr0
  post-up /sbin/ip -f inet6 neigh add proxy 2001:xxx:xxx:100::3 dev enp1s0
  post-up /sbin/ip -f inet6 route add       2001:xxx:xxx:100::3 dev vmbr0
```

7. Install `qemu` and `libvirt`

```bash
apt install --no-install-recommends qemu-system libvirt-clients libvirt-daemon-system virtinst qemu-utils
```


8. Create your first virtual machine with `virt-install`

```bash
virt-install --virt-type kvm --name bookworm-amd64 --location https://deb.debian.org/debian/dists/bookworm/main/installer-amd64/ --os-variant debian11 --disk size=10 --memory 512 --graphics none --console pty,target_type=serial --extra-args "console=ttyS0" --bridge vmbr0
```

* Fixed IPv6: `2001:xxx:xxx:100::3/64`
* Gateway: `2001:xxx:xxx:100::2`

You can use the DNS set-up by the installer on the host, in `/etc/resolv.conf`, add

```
nameserver 2001:xxx:xxx:100::2
```
