---
title: "Create a private network with Headscale and Tailscale"
date: 2025-01-30
draft: false
tags: [sysadmin, network, linux]
toc: true
---

This post describes the usage of [`headscale`](https://headscale.net/stable/) and [`tailscale`](https://github.com/tailscale/tailscale) to create a virtual network based on [WireGuard](https://www.wireguard.com/).

<!--more-->

## Installation

One `headscale` server node is needed, nodes will be registered on this server using `tailscale`.

The couple `headscale`/`tailscale` permits to establish WireGuard tunnels between all the registered nodes.
If a direct connection between two nodes is not possible, `headscale` supports "DERP" to relay the traffic between these two nodes.
`headscale` also supports ["MagicDNS"](https://tailscale.com/kb/1081/magicdns), and can automatically map nodes to domain names.

### Headscale server

Follow the [instructions here](https://headscale.net/development/setup/install/official/).
In example for Debian 12:

1. Install the package

```bash-session
# HEADSCALE_VERSION="0.24.2"
# HEADSCALE_ARCH="amd64"
# wget --output-document=headscale.deb \
#  "https://github.com/juanfont/headscale/releases/download/v${HEADSCALE_VERSION}/headscale_${HEADSCALE_VERSION}_linux_${HEADSCALE_ARCH}.deb"
# apt install ./headscale.deb
```

2. Configure `headscale` by editing the configuration file `/etc/headscale/config.yaml`.

The important configuration variables are:

  * `server_url`, in my case `https://flip.flap42.eu:8080`
  * `listen_addr`, set to `0.0.0.0:8080`
  * `tls_letsencrypt_hostname`, this is the domain used for the TLS certificate with let's encrypt, I've used `flip.flap42.eu`
  * `prefixes`, these are the prefix used on your network, they must be contained in `100.64.0.0/10` and `fd7a:115c:a1e0::/48`. In my case, I've set the v6 prefix to `fd28:7515:7d51:42::/64`, which is officially unsupported but functional anyway.
  * `magic_dns`, set to "true" to enable its support
    * `base_domain`, base domain used for the magic dns records
    * `nameservers`, list of forwarders

3. Enable the service

```bash-session
# systemctl enable --now headscale
```

4. Verify the service status and read the logs

```bash-session
# systemctl status headscale
# journalctl -u headscale.service -f -n 100
```

### Tailscale client

You can choose [the appropriated repository for your system here](https://pkgs.tailscale.com/stable/), for Debian 12:

```bash-session
# curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
# curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
# apt update
# apt install tailscale
# systemctl status tailscaled
```

The `tailscaled` service is enabled by default.

## Register the nodes

1. Create users on the server node

Create users

```bash-session
# headscale user create nl-ams1
User created
# headscale user create nl-ams1
User created
# headscale user create nl-ams2
User created
```

2. Use the `tailscale` client on the client node to login to the server. It will open a browser with the registration instructions for the `headscale` server.

```bash-session
# tailscale up --login-server https://flip.flap42.eu:8080
```

![Tailscale brower window with key](headscale.png)

3. Register the node on the server node, using the previously generated key

```bash-session
# headscale nodes register --user nl-ams2 --key mkey:**KEY**
Node nl-ams2 registered
```

4. On the client node, use these commands to verify the allocated IPs

```bash-session
$ tailscale ip -4
100.64.0.3
$ tailscale ip -6
fd28:7515:7d51:42::3
```

As an alternative, you can use preauthorized keys:

1. Generate preauthorized keys on the server node

```bash-session
# headscale preauthkeys create -u nl-ams1
2025-01-26T22:21:30+01:00 TRC expiration has been set expiration=3600000
***KEY***
```

2. Use the key on the client node to login

```bash-session
# tailscale up --login-server https://flip.flap42.eu:8080 --authkey **KEY** 
```

## Test the virtual network

1. On the server node, you can list all clients with the command `headscale node list`

```bash-session
# headscale node list
ID | Hostname | Name     | MachineKey | NodeKey | User      | IP addresses                     | Ephemeral | Last seen           | Expiration          | Connected | Expired
1  | hc-xps15 | hc-xps15 | [*****]    | [*****] | hcartiaux | 100.64.0.3, fd28:7515:7d51:42::3 | false     | 2025-01-26 21:45:52 | 0001-01-01 00:00:00 | online    | no
2  | nl-ams2  | nl-ams2  | [*****]    | [*****] | nl-ams2   | 100.64.0.4, fd28:7515:7d51:42::4 | false     | 2025-01-26 21:45:52 | 0001-01-01 00:00:00 | online    | no
3  | nl-ams1  | nl-ams1  | [*****]    | [*****] | nl-ams1   | 100.64.0.5, fd28:7515:7d51:42::5 | false     | 2025-01-26 21:45:52 | 0001-01-01 00:00:00 | online    | no
```

2. On the client nodes, `tailscale` create a new network interface `tailscale0` and configures the allocated address

```bash-session
$ ip -br -c a
...
tailscale0       UNKNOWN        100.64.0.4/32 fd28:7515:7d51:42::4/128 fe80::5c6e:ccf5:de0:ea97/64
```

3. All client nodes can reach all the other nodes which are part of the network, using the "MagicDNS"

```bash-session
$ ping -c3 nl-ams1.flip.flap42.eu
PING nl-ams1.flip.flap42.eu (100.64.0.5) 56(84) bytes of data.
64 bytes from nl-ams1.flip.flap42.eu (100.64.0.5): icmp_seq=1 ttl=64 time=4.61 ms
64 bytes from nl-ams1.flip.flap42.eu (100.64.0.5): icmp_seq=2 ttl=64 time=1.85 ms
64 bytes from nl-ams1.flip.flap42.eu (100.64.0.5): icmp_seq=3 ttl=64 time=1.77 ms

--- nl-ams1.flip.flap42.eu ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2003ms
rtt min/avg/max/mdev = 1.774/2.741/4.605/1.317 ms
```

