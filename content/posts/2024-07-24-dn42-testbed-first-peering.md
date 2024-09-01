---
title: "[dn42] AS4242420263 configuration - speedrun to the first peering session (Part 2/5)"
date: 2024-07-24
draft: false
tags: [homelab, sysadmin, network, dn42]
toc: true
---

This article is the 2nd part of my dn42 experiment and will present all my configuration notes from the initial set-up of my first router server to my first peering session on dn42.

<!--more-->

As a reminder, all my dn42 routers configurations are [backed-up in this github repository](https://github.com/hcartiaux/dn42-as4242420263).

## Network information

| ASN            | Block                 | Primary name server   | Secondary name server |
|----------------|-----------------------|-----------------------|-----------------------|
| `AS4242420263` | `fd28:7515:7d51::/48` | `fd28:7515:7d51:a::1` | `fd28:7515:7d51:c::1` |
| `AS4242420263` | `172.22.144.160/27`   | `172.22.144.161`      | `172.22.144.177`      |

I've split my blocks in 4 equal size subnets:

| Desc. | IPv6 Network            | IPv6 Gateway             | IPv4 Network        | IPv4 Gateway        |
|-------|-------------------------|--------------------------|---------------------|---------------------|
| `gw`  | `fd28:7515:7d51:a::/64` | `fd28:7515:7d51:a::1/64` | `172.22.144.160/29` | `172.22.144.161/29` |
| `gw`  | `fd28:7515:7d51:b::/64` | `fd28:7515:7d51:b::1/64` | `172.22.144.168/29` | `172.22.144.169/29` |
| `gw2` | `fd28:7515:7d51:c::/64` | `fd28:7515:7d51:c::1/64` | `172.22.144.176/29` | `172.22.144.177/29` |
| `gw2` | `fd28:7515:7d51:d::/64` | `fd28:7515:7d51:d::1/64` | `172.22.144.184/29` | `172.22.144.185/29` |


In this post, I will only describe the first `gw` router configuration.

## First connection

### Pre-requisites, server configuration

#### Kernel parameters

1. Create two files in `/etc/sysctl.d`:

    * `/etc/sysctl.d/ipv4.conf` - enable packets forwarding and disable reverse path filtering (asymetric routing might happens when using several bgp peers)
    ```
    net.ipv4.ip_forward=1
    net.ipv4.conf.all.rp_filter=0
    net.ipv4.conf.default.rp_filter=0
    ```

    * `/etc/sysctl.d/ipv6.conf` - enable packets forwarding and disable IPv6 auto configuration
    ```
    net.ipv6.conf.all.forwarding=1
    net.ipv6.conf.all.autoconf=0
    ```

2. Load these parameters with the command `sysctl --system`


#### Wireguard

* Install wireguard and its tools

```bash
apt install wireguard wireguard-tools
```

* Generate a set of public and private keys

```bash
cd /etc/wireguard/
umask 077; wg genkey | tee privatekey | wg pubkey > publickey
```

### Automated peering service

To simplify the procedure, I've used automated peering services. For the sake of efficiency, choose a peering point located near your server with a low latency (<30ms).

* [Kioubit Network](https://dn42.g-load.eu/)
* [Sunnet dn42](https://peer.dn42.6700.cc/)
* [JK-Network](https://net.whojk.com/)
* [Lare](https://dn42.lare.cc/dn42/nodes/)
* [Tech9](https://www.chrismoos.com/dn42-peering/) (no support for extended next hop, specific configuration required)

Note, even if the peering service is automated, the configuration may not be changed and reloaded immediately.
If it does not work immediately, either wait or try to create another peering with another service.
As an example, I will peer with Kioubit. I've followed the instructions to access the peering dashboard and ended with these peering information:


| **Kioubit's Side**       |                                                 |
|--------------------------|-------------------------------------------------|
| AS-Number                | 4242423914                                      |
| Endpoint Address         | fr1.g-load.eu:20263                             |
| Wireguard Public Key     | sLbzTRr2gfLFb24NPzDOpy8j09Y6zI+a7NkeVMdVSR8=    |
| Tunnel IPv6 (Link-Local) | fe80::ade0                                      |

{{< rawhtml >}}
<br />
{{< /rawhtml >}}

| **Our Side**             |                                                 |
|--------------------------|-------------------------------------------------|
| Wireguard Public Key     | 8JNlIxV5BTOxNBB2wDs/A5HSvzcZxSLbIEVzz7b94Qc=    |
| Tunnel IPv6              | fe80::101                                       |
| Multiprotocol BGP        | Enabled                                         |
| Extended next hop        | Enabled                                         |

### Set-up the router IPs on a loopback interface

Create a new file `/etc/network/interfaces.d/loopback.dn42`:

```
auto lo:10

iface lo:10 inet static
    address 172.22.144.161
    netmask 255.255.255.248
    network 172.22.144.160

iface lo:10 inet6 static
    address fd28:7515:7d51:a::1/64
```

And bring it up

```
ifup lo:10
```

### Establish a wireguard tunnel

I create one wireguard endpoint per peering link, in order to monitor each link independently.

* Create a new file `/etc/wireguard/wg-peer-kioubit.conf`
  * `PrivateKey`: paste the content of the file `/etc/wireguard/privatekey`
  * `ListenPort`: choose an unused port
  * `PostUp`: set the IP on the tunnel network interface.
  * `Table = off`: do not modify the system routing tables, **mandatory to avoid conflicting with `bird2`**
  * Peer `PublicKey`: Kioubit's public key
  * Peer `EndPoint`: Kioubit's endpoint address and port
  * `PersistentKeepalive = 30`: send a packet every 30 seconds, [required when NAT is involved for the firewall traversal persistence](https://www.wireguard.com/quickstart/#nat-and-firewall-traversal-persistence)
  * `AllowedIPs`: List of allowed networks on the tunnel

```
[Interface]
PrivateKey = **REDACTED**
ListenPort = 51821
PostUp = /sbin/ip addr add dev %i fe80::101/128 peer fe80::ade0/128
Table = off

# Kioubit
[Peer]
PublicKey = sLbzTRr2gfLFb24NPzDOpy8j09Y6zI+a7NkeVMdVSR8=
Endpoint = fr1.g-load.eu:20263
PersistentKeepalive = 30
AllowedIPs = 172.16.0.0/12, 10.0.0.0/8, fd00::/8, fe80::/10
```

* Start the tunnel at boot time (and immediately if not started):

```bash
systemctl enable --now wg-quick@wg-peer-kioubit
```

* The tunnel should be established, the lines "latest handshake" and "transfer" will appear and be refreshed.

```bash-session
wg show wg-peer-kioubit
interface: wg-peer-kioubit
  public key: 8JNlIxV5BTOxNBB2wDs/A5HSvzcZxSLbIEVzz7b94Qc=
  private key: (hidden)
  listening port: 51821

peer: sLbzTRr2gfLFb24NPzDOpy8j09Y6zI+a7NkeVMdVSR8=
  endpoint: [2001:41d0:2:36e::1]:20263
  allowed ips: 172.16.0.0/12, 10.0.0.0/8, fd00::/8, fe80::/10
  latest handshake: 1 minute, 18 seconds ago
  transfer: 331.89 KiB received, 315.65 KiB sent
  persistent keepalive: every 30 seconds
```

* The network interface `wg-peer-kioubit` is up.

```bash-session
ip address show dev wg-peer-kioubit
8: wg-peer-kioubit: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1420 qdisc noqueue state UNKNOWN group default qlen 1000
    link/none 
    inet6 fe80::101 peer fe80::ade0/128 scope link
       valid_lft forever preferred_lft forever
```

* The peer link-local IPv6 address is pingable.

```bash-session
ping -c1  fe80::ade0
PING fe80::ade0(fe80::ade0) 56 data bytes
64 bytes from fe80::ade0%wg-peer-kioubit: icmp_seq=1 ttl=64 time=5.20 ms

--- fe80::ade0 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 5.203/5.203/5.203/0.000 ms
```

* Debug tips:
    * if the wireguard tunnel is established but the IPv6 is not pingable, use `tcpdump -i wg-peer-kioubit` to see and understand what's passing on the link
    * if the wireguard tunnel is not functional, 9 times out of 10, it's a typo in the private key or in the peer public key, double check the keys
    * enable wireguard debug mode and read the kernel messages:
    ```
      echo module wireguard +p > /sys/kernel/debug/dynamic_debug/control
      dmesg -WHT
      echo module wireguard -p > /sys/kernel/debug/dynamic_debug/control
    ```


### Install `bird2` (the routing daemon) and a basic configuration

In the next sections, I've compiled information scattered on the dn42 wiki [especially the `bird2` documentation page](https://dn42.eu/howto/Bird2), various [web pages](https://jlu5.com/blog/dn42-multiple-servers-ibgp-igps) and [blog posts](https://mk16.de/blog/dn42-beginner-tips/).

```bash
apt install bird2
```

The entry point of the configuration is the file `/etc/bird/bird.conf`, it's a generic file which includes many others:

* `variables.conf`: definitions of configuration variables related to the local AS and networks
* `utilities.conf`: useful functionsV
* `roa.conf` - Route Origin Authorization configuration, [described in the section below](#set-up-route-origin-authorization-roa)
* `bgp_community_filters.conf` - route import and export filters functions, [described in a section below](#create-the-importexport-filter-functions-using-bgp-community-flags-and-roa-checks)
* `bgp_peers/*` 

#### Skeleton file `/etc/bird/bird.conf`

This configuration file does not contain any network-specific settings and can be used as-is.

```
# This is AS4242420263 bird configuration file on the DN42 overlay network.
#
# Please refer to the BIRD User's Guide documentation, which is also available
# online at http://bird.network.cz/ in HTML format, for more information on
# configuring BIRD and adding routing protocols.

# Configure logging
# log syslog all;
# log stderr all;
# debug protocols all;

# local configuration
######################

# keeping router specific in a seperate file,
# so this configuration can be reused on multiple routers in your network
include "/etc/bird/variables.conf";

# Convenient functions
include "/etc/bird/utilities.conf";

# Router configuration
######################

router id OWNIP;

# Device status
protocol device {
    scan time 10;
}

# Kernel routing tables
########################

# The Kernel protocol is not a real routing protocol. Instead of communicating
# with other routers in the network, it performs synchronization of BIRD's
# routing tables with the OS kernel.
protocol kernel {
    scan time 20;

    ipv4 {
        import none;
        export filter {
            if source = RTS_STATIC then {
                print "Static route filtered: ", net;
                reject;
            }
            /*
                krt_prefsrc defines the source address for outgoing connections.
                On Linux, this causes the "src" attribute of a route to be set.

                Without this option outgoing connections would use the peering IP which
                would cause packet loss if some peering disconnects but the interface
                is still available. (The route would still exist and thus route through
                the TUN/TAP interface but the VPN daemon would simply drop the packet.)
            */
            krt_prefsrc = OWNIP;
            accept;
        };
    };
}

protocol kernel {
    scan time 20;

    ipv6 {
        import none;
        export filter {
            if source = RTS_STATIC then {
                print "Static route filtered: ", net;
                reject;
            }
            krt_prefsrc = OWNIPv6;
            accept;
        };
    };
};

# Static routes
###############

protocol static {
    route OWNNET reject;

    ipv4 {
        import all;
        export none;
    };
}

protocol static {
    route OWNNETv6 reject;

    ipv6 {
        import all;
        export none;
    };
}


# Include ROA tables definition
###############################

include "/etc/bird/roa.conf";


# BGP - DN42 peers
##################

# Community and import filters
include "/etc/bird/bgp_community_filters.conf";

template bgp dnpeers {
    local as OWNAS;
    # metric is the number of hops between us and the peer
    path metric 1;
    ipv4 {
        import limit 9000 action block;
        import table;
    };

    ipv6 {
        import limit 9000 action block;
        import table;
    };
}

include "/etc/bird/bgp_peers/*";
```

#### Local configuration file `variables.conf`

This is my dn42 AS and IPv4 and v6 networks information.
These variables are used in the rest of the configuration.


```
# Configuration variables
#########################

define OWNAS       = 4242420263;

define OWNIP       = 172.22.144.161;
define OWNNET      = 172.22.144.160/27;
define OWNNETSET   = [172.22.144.160/27+];

define OWNNETv6    = fd28:7515:7d51::/48;
define OWNIPv6     = fd28:7515:7d51:a::1;
define OWNNETSETv6 = [fd28:7515:7d51::/48+];

# BGP community
define BANDWIDTH   = 24;   # >= 100Mbps
define LINKTYPE    = 34;   # encrypted with safe vpn solution with PFS (Perfect Forward Secrecy)
define REGION      = 41;   # Europe
define COUNTRY     = 1250; # France (ISO-3166-1 numeric country code + 1000)
```

For the BGP communities values `BANDWIDTH`, `LINKTYPE`, `REGION` and `COUNTRY`, [see the section below to choose the good values](#create-the-importexport-filter-functions-using-bgp-communities).

#### `utilities.conf`

This file contains useful functions for writing import/export route filters.

```
function is_self_net() {
    return net ~ OWNNETSET;
}

function is_valid_network() {
    return net ~ [
        172.20.0.0/14{21,29}, # dn42
        172.20.0.0/24{28,32}, # dn42 Anycast
        172.21.0.0/24{28,32}, # dn42 Anycast
        172.22.0.0/24{28,32}, # dn42 Anycast
        172.23.0.0/24{28,32}, # dn42 Anycast
        172.31.0.0/16+,       # ChaosVPN
        10.100.0.0/14+,       # ChaosVPN
        10.127.0.0/16{16,32}, # neonetwork
        10.0.0.0/8{15,24}     # Freifunk.net
    ];
}

function is_self_net_v6() {
    return net ~ OWNNETSETv6;
}

function is_valid_network_v6() {
    return net ~ [
        fd00::/8{44,64} # ULA address space as per RFC 4193
    ];
}
```

#### Set-up Route Origin Authorization (ROA)

*Route Origination Authorization* is a mechanism that states which Autonomous System (AS) is authorized to originate a particular IP address prefix or set of prefixes.
In this section, I set up ROA in a naive way, but [it's possible to go further and use the RTR protocol](https://dn42.eu/howto/ROA-slash-RPKI).

* In the file `/etc/bird/roa.conf`, we configure the ROA tables for IPv4 and IPv6, to be populated from a configuration file.

```
roa4 table dn42_roa;
roa6 table dn42_roa_v6;

protocol static {
    roa4 { table dn42_roa; };
    include "/etc/bird/roa/roa_dn42.conf";
};

protocol static {
    roa6 { table dn42_roa_v6; };
    include "/etc/bird/roa/roa_dn42_v6.conf";
};
```

Refresh the ROA configuration files with a script and systemd timer.

* Create a script `/usr/local/bin/dn42-roa-update.sh` and make it executable (`chmod +x /usr/local/bin/dn42-roa-update.sh`)

```bash
#!/bin/bash
roa4URL="https://dn42.burble.com/roa/dn42_roa_bird2_4.conf"
roa6URL="https://dn42.burble.com/roa/dn42_roa_bird2_6.conf"

dirname="/etc/bird/roa"
roa4FILE="${dirname}/roa_dn42.conf"
roa6FILE="${dirname}/roa_dn42_v6.conf"

mkdir -p "${dirname}"

cp "${roa4FILE}" "${roa4FILE}.old"
cp "${roa6FILE}" "${roa6FILE}.old"

if curl -f -o "${roa4FILE}.new" "${roa4URL}" ;then
    diff "${roa4FILE}.new" "${roa4FILE}"
    mv "${roa4FILE}.new" "${roa4FILE}"
fi

if curl -f -o "${roa6FILE}.new" "${roa6URL}" ;then
    diff "${roa6FILE}.new" "${roa6FILE}"
    mv "${roa6FILE}.new" "${roa6FILE}"
fi

if birdc configure ; then
    rm "${roa4FILE}.old"
    rm "${roa6FILE}.old"
else
    mv "${roa4FILE}.old" "${roa4FILE}"
    mv "${roa6FILE}.old" "${roa6FILE}"
fi
```

* Create a systemd service file `/etc/systemd/system/dn42-roa.service`

```
[Unit]
Description=Update DN42 ROA

[Service]
Type=oneshot
ExecStart=/usr/local/bin/dn42-roa-update.sh
```

* Create a systemd timer file `/etc/systemd/system/dn42-roa.timer`

```
[Unit]
Description=Update DN42 ROA periodically

[Timer]
OnBootSec=2m
OnUnitActiveSec=15m
AccuracySec=1m

[Install]
WantedBy=timers.target
```

* Enable the timer

```bash-session
systemctl enable --now dn42-roa.timer

systemctl list-timers dn42-roa.timer
NEXT                         LEFT      LAST                         PASSED   UNIT           ACTIVATES
Sat 2024-07-20 15:36:47 CEST 6min left Sat 2024-07-20 15:21:47 CEST 8min ago dn42-roa.timer dn42-roa.service

1 timers listed.
```

* The ROA configuration files are now populated

```bash-session
wc -l /etc/bird/roa/roa_dn42{,_v6}.conf
  2638 /etc/bird/roa/roa_dn42.conf
  2499 /etc/bird/roa/roa_dn42_v6.conf
  5137 total
```

#### Create the import/export filter functions combining BGP communities and ROA checks

This is heavily based on the [official dn42 wiki](https://dn42.eu/howto/BGP-communities), though slightly modified.

These functions will be re-used in each BGP peering session configuration, they're used to filter the routes to be imported or exported **and** to set the communities attributes based on the parameters.
The difficulty is to write the following functions to combine the ROA checks and update the BGP communities at the same time:

* `function dn42_import_filter(int link_latency; int link_bandwidth; int link_crypto)`
* `function dn42_export_filter(int link_latency; int link_bandwidth; int link_crypto)`
* `function dn42_import_filter_v6(int link_latency; int link_bandwidth; int link_crypto)`
* `function dn42_export_filter_v6(int link_latency; int link_bandwidth; int link_crypto)`

BGP allows to set "community" attribues to each routes, a community is a set of two 16-bits number.
By convention, dn42 uses `64511` for the first community number, and define "flags" for the second number, mainly latency, bandwidth, encryption level, region and country.
The trafic can then be routed differently based on the communities attributes set on the relevant route.

Here are the parameters values to be used with the import/export filter functions:

```
(64511, 1) :: latency \in (0, 2.7ms]
(64511, 2) :: latency \in (2.7ms, 7.3ms]
(64511, 3) :: latency \in (7.3ms, 20ms]
(64511, 4) :: latency \in (20ms, 55ms]
(64511, 5) :: latency \in (55ms, 148ms]
(64511, 6) :: latency \in (148ms, 403ms]
(64511, 7) :: latency \in (403ms, 1097ms]
(64511, 8) :: latency \in (1097ms, 2981ms]
(64511, 9) :: latency > 2981ms
(64511, x) :: latency \in [exp(x-1), exp(x)] ms (for x < 10)

(64511, 21) :: bw >= 0.1mbit
(64511, 22) :: bw >= 1mbit
(64511, 23) :: bw >= 10mbit
(64511, 24) :: bw >= 100mbit
(64511, 25) :: bw >= 1000mbit
(64511, 2x) :: bw >= 10^(x-2) mbit
bw = min(up,down) for asymmetric connections

(64511, 31) :: not encrypted
(64511, 32) :: encrypted with unsafe vpn solution
(64511, 33) :: encrypted with safe vpn solution (but no PFS - the usual OpenVPN p2p configuration falls in this category)
(64511, 34) :: encrypted with safe vpn solution with PFS (Perfect Forward Secrecy)

Propagation:
- - for latency pick max(received_route.latency, link_latency)
- - for encryption and bandwidth pick min between received BGP community and peer link
```

* Content of the file `/etc/bird/bgp_community_filters.conf`

```
function update_latency(int link_latency) {
    bgp_community.add((64511, link_latency));
         if (64511, 9) ~ bgp_community then { bgp_community.delete([(64511, 1..8)]); return 9; }
    else if (64511, 8) ~ bgp_community then { bgp_community.delete([(64511, 1..7)]); return 8; }
    else if (64511, 7) ~ bgp_community then { bgp_community.delete([(64511, 1..6)]); return 7; }
    else if (64511, 6) ~ bgp_community then { bgp_community.delete([(64511, 1..5)]); return 6; }
    else if (64511, 5) ~ bgp_community then { bgp_community.delete([(64511, 1..4)]); return 5; }
    else if (64511, 4) ~ bgp_community then { bgp_community.delete([(64511, 1..3)]); return 4; }
    else if (64511, 3) ~ bgp_community then { bgp_community.delete([(64511, 1..2)]); return 3; }
    else if (64511, 2) ~ bgp_community then { bgp_community.delete([(64511, 1..1)]); return 2; }
    else return 1;
}

function update_bandwidth(int link_bandwidth)
int local_bandwidth ; {
    if link_bandwidth > BANDWIDTH then local_bandwidth = BANDWIDTH;
    else local_bandwidth = link_bandwidth;

    bgp_community.add((64511, local_bandwidth));
         if (64511, 21) ~ bgp_community then { bgp_community.delete([(64511, 22..29)]); return 21; }
    else if (64511, 22) ~ bgp_community then { bgp_community.delete([(64511, 23..29)]); return 22; }
    else if (64511, 23) ~ bgp_community then { bgp_community.delete([(64511, 24..29)]); return 23; }
    else if (64511, 24) ~ bgp_community then { bgp_community.delete([(64511, 25..29)]); return 24; }
    else if (64511, 25) ~ bgp_community then { bgp_community.delete([(64511, 26..29)]); return 25; }
    else if (64511, 26) ~ bgp_community then { bgp_community.delete([(64511, 27..29)]); return 26; }
    else if (64511, 27) ~ bgp_community then { bgp_community.delete([(64511, 28..29)]); return 27; }
    else if (64511, 28) ~ bgp_community then { bgp_community.delete([(64511, 29..29)]); return 28; }
    else return 29;
}

function update_crypto(int link_crypto) {
    bgp_community.add((64511, link_crypto));
         if (64511, 31) ~ bgp_community then { bgp_community.delete([(64511, 32..34)]); return 31; }
    else if (64511, 32) ~ bgp_community then { bgp_community.delete([(64511, 33..34)]); return 32; }
    else if (64511, 33) ~ bgp_community then { bgp_community.delete([(64511, 34..34)]); return 33; }
    else return 34;
}

function update_flags(int link_latency; int link_bandwidth; int link_crypto)
{
    update_latency(link_latency);
    update_bandwidth(link_bandwidth);
    update_crypto(link_crypto);
    return true;
}

function update_route_origin(int region; int country)
{
    bgp_community.add((64511, region));
    bgp_community.add((64511, country));
}

# IPv4 filters

function dn42_import_filter(int link_latency; int link_bandwidth; int link_crypto) {
    # accept every valid subnets except our own advertised subnet
    if is_valid_network() && !is_self_net() then {
        # Reject when invalid according to ROA
        if (roa_check(dn42_roa, net, bgp_path.last) != ROA_VALID) then {
            print "[dn42] ROA check failed for ", net, " ASN ", bgp_path.last;
            reject;
        } else {
            update_flags(link_latency, link_bandwidth, link_crypto);
            accept;
        }
    } else reject;
}

function dn42_export_filter(int link_latency; int link_bandwidth; int link_crypto) {
    if (is_valid_network() && source ~ [RTS_STATIC, RTS_BGP]) then {
        # Set the route origin for routes originating from our network
        if source = RTS_STATIC then update_route_origin(REGION, COUNTRY);
        # Set the other community flags
        update_flags(link_latency, link_bandwidth, link_crypto);
        accept;
    } else {
        reject;
    }
}

# IPv6 filters

function dn42_import_filter_v6(int link_latency; int link_bandwidth; int link_crypto) {
    # accept every valid subnets except our own advertised subnet
    if is_valid_network_v6() && !is_self_net_v6() then {
        # Reject when invalid according to ROA
        if (roa_check(dn42_roa_v6, net, bgp_path.last) != ROA_VALID) then {
            print "[dn42] ROA check failed for ", net, " ASN ", bgp_path.last;
            reject;
        } else {
            update_flags(link_latency, link_bandwidth, link_crypto);
            accept;
        }
    } else reject;
}

function dn42_export_filter_v6(int link_latency; int link_bandwidth; int link_crypto) {
    if (is_valid_network_v6()  && source ~ [RTS_STATIC, RTS_BGP]) then {
        if source = RTS_STATIC then update_route_origin(REGION, COUNTRY);
        update_flags(link_latency, link_bandwidth, link_crypto);
        accept;
    } else {
        reject;
    }
}
```

### Configure the first BGP peering session

Create one file per BGP peering session, the configuration for Kioubit is stored in the file `/etc/bird/bgp_peers/kioubit.dn42`:

* the latency depends on the link, measure it by pinging the neighbor link-local address and set the appropriate value for the BGP community
* MBGP (Multiprotocol BGP) is supported, bird can create an IPv4 channel and an IPv6 channel in the same BGP session
* [Extended Next Hop](https://www.bortzmeyer.org/8950.html) is also supported, IPv4 traffic can be routed via an IPv6 hop, so it's not needed to set-up an IPv4 on the peering link.

```
define KIOUBIT_LATENCY = 2; # latency in [2.7ms, 7.3ms]

protocol bgp kioubit_v6 from dnpeers {
    neighbor fe80::ade0 as 4242423914;
    interface "wg-peer-kioubit";

    ipv4 {
        import where dn42_import_filter(KIOUBIT_LATENCY, BANDWIDTH, LINKTYPE);
        export where dn42_export_filter(KIOUBIT_LATENCY, BANDWIDTH, LINKTYPE);
        extended next hop on;
    };

    ipv6 {
        import where dn42_import_filter_v6(KIOUBIT_LATENCY, BANDWIDTH, LINKTYPE);
        export where dn42_export_filter_v6(KIOUBIT_LATENCY, BANDWIDTH, LINKTYPE);
        extended next hop off;
    };
}
```

* Enable the `bird` service

```bash
systemctl enable --now bird
```

* Use `birdc` to query the bird routing daemon state

```bash-session
birdc show status
BIRD 2.0.12 ready.
BIRD 2.0.12
Router ID is 172.22.144.161
Hostname is gw-dn42
Current server time is 2024-07-21 00:45:07.047
Last reboot on 2024-07-21 00:21:37.824
Last reconfiguration on 2024-07-21 00:37:06.363
Daemon is up and running
```

* Query the status of the peering session with Kioubit

```bash-session
birdc show protocols all kioubit_v6
Name       Proto      Table      State  Since         Info
kioubit_v6 BGP        ---        up     00:21:41.333  Established
  BGP state:          Established
    Neighbor address: fe80::ade0%wg-peer-kioubit
    Neighbor AS:      4242423914
    Local AS:         4242420263
    Neighbor ID:      172.20.53.102
    Local capabilities
      Multiprotocol
        AF announced: ipv4 ipv6
      Route refresh
      Extended next hop
        IPv6 nexthop: ipv4
      Graceful restart
      4-octet AS numbers
      Enhanced refresh
      Long-lived graceful restart
    Neighbor capabilities
      Multiprotocol
        AF announced: ipv4 ipv6
      Route refresh
      Extended next hop
        IPv6 nexthop: ipv4
      Graceful restart
      4-octet AS numbers
      Enhanced refresh
      Long-lived graceful restart
    Session:          external AS4
    Source address:   fe80::101
    Hold timer:       232.893/240
    Keepalive timer:  4.029/80
  Channel ipv4
    State:          UP
    Table:          master4
    Preference:     100
    Input filter:   (unnamed)
    Output filter:  (unnamed)
    Import limit:   9000
      Action:       block
    Routes:         761 imported, 541 exported, 276 preferred
    Route change stats:     received   rejected   filtered    ignored   accepted
      Import updates:           2838          0          6         25       2807
      Import withdraws:            2          0        ---          2          0
      Export updates:           3424        820         16        ---       2588
      Export withdraws:            6        ---        ---        ---         54
    BGP Next hop:   :: fe80::101
  Channel ipv6
    State:          UP
    Table:          master6
    Preference:     100
    Input filter:   (unnamed)
    Output filter:  (unnamed)
    Import limit:   9000
      Action:       block
    Routes:         745 imported, 490 exported, 257 preferred
    Route change stats:     received   rejected   filtered    ignored   accepted
      Import updates:            892          0          2         17        873
      Import withdraws:            2          0        ---          2          0
      Export updates:           1498        809         16        ---        673
      Export withdraws:            2        ---        ---        ---         54
    BGP Next hop:   :: fe80::101
```

* Show the routes exchanged with `kioubit` by querying `bird`

```bash
birdc show route protocol kioubit_v6
```

* Check the local routing table of the system, and see all the imported routes

```bash
ip route | grep -i wg-peer-kioubit
```

## Access dn42 internal services

### DNS servers

[See the documentation here](https://dn42.eu/services/DNS).

| Name                      | IPv4        | IPv6               |
|---------------------------|-------------|--------------------|
| a0.recursive-servers.dn42 | 172.20.0.53 | fd42:d42:d42:54::1 |
| a3.recursive-servers.dn42 | 172.23.0.53 | fd42:d42:d42:53::1 |

Verify that the DNS servers are reachable.

```bash-session
ip route get fd42:d42:d42:54::1
fd42:d42:d42:54::1 from :: via fe80::ade0 dev wg-peer-kioubit proto bird src fd28:7515:7d51:a::1 metric 32 pref medium

ping -c1 fd42:d42:d42:54::1
PING fd42:d42:d42:54::1(fd42:d42:d42:54::1) 56 data bytes
64 bytes from fd42:d42:d42:54::1: icmp_seq=1 ttl=63 time=5.18 ms

--- fd42:d42:d42:54::1 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 5.178/5.178/5.178/0.000 ms
```

Try to query the DNS server

```bash-session
dig -tAAAA burble.dn42 @fd42:d42:d42:54::1

; <<>> DiG 9.18.24-1-Debian <<>> -tAAAA burble.dn42 @fd42:d42:d42:54::1
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 63469
;; flags: qr rd ra ad; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 512
;; QUESTION SECTION:
;burble.dn42.                   IN      AAAA

;; ANSWER SECTION:
burble.dn42.            3517    IN      AAAA    fd42:4242:2601:ac80::1

;; Query time: 7 msec
;; SERVER: fd42:d42:d42:54::1#53(fd42:d42:d42:54::1) (UDP)
;; WHEN: Sat Jul 20 23:02:27 CEST 2024
;; MSG SIZE  rcvd: 68

```

If yes, set the server with the lowest latency first in the `/etc/resolv.conf`.

```
nameserver fd42:d42:d42:54::1
nameserver fd42:d42:d42:53::1
nameserver 172.20.0.53
nameserver 172.23.0.53
search dn42
```

If `/etc/resolv.conf` is managed by `systemd-resolve`, then modify the file `/etc/systemd/resolved.conf` and change these lines

```
DNS=fd42:d42:d42:54::1 fd42:d42:d42:53::1 172.20.0.53 172.23.0.53
Domains=dn42
```

### Burble shell

Many [internal services](https://internal.dn42/internal/Internal-Services) are hosted on dn42, the ["burble shell servers"](https://dn42.burble.com/services/shell/) are very convenient and located in many different geographic areas.

The login name is your `mntner` name, lowercase, without the `-MNT` suffix (`HCARTIAUX-MNT` → `hcartiaux`)

This service can be used:

* to play [Colossal Cave Adventure](https://rickadams.org/adventure/), a piece of computer games history:
```bash-session
ssh hcartiaux@shell.fr.burble.dn42
bsdgames-adventure

Welcome to Adventure!!  Would you like instructions?
yes

Somewhere nearby is Colossal Cave, where others have found fortunes in
treasure and gold, though it is rumored that some who enter are never
seen again.  Magic is said to work in the cave.  I will be your eyes
and hands.  Direct me with commands of 1 or 2 words.  I should warn
you that I look at only the first five letters of each word, so you'll
have to enter "northeast" as "ne" to distinguish it from "north".
(Should you get stuck, type "help" for some general hints.  For
information on how to end your adventure, etc., type "info".)
                              - - -
This program was originally developed by Will Crowther.  Most of the
features of the current program were added by Don Woods.  Address
complaints about the UNIX version to Jim Gillogly (jim@rand.org).

You are standing at the end of a road before a small brick building.
Around you is a forest.  A small stream flows out of the building and
down a gully.
```

* to host files over http:
```bash
ssh hcartiaux@shell.fr.burble.dn42
mkdir ~/public_html
echo See you space cowboy > index.html
```

In local:
```bash-session
curl -k https://shell.fr.burble.dn42/~hcartiaux/
See you space cowboy
```

* to run network commands from other points of the dn42 network
```bash-session
ssh hcartiaux@shell.lax.burble.dn42
tracepath -n fd28:7515:7d51:a::1
 1?: [LOCALHOST]                        0.039ms pmtu 4260
 1:  fd42:4242:2601:1018::1                                0.262ms
 1:  fd42:4242:2601:1018::1                                0.212ms
 2:  fd42:4242:2601:1018::1                                0.218ms pmtu 1420
 2:  fd42:4242:2601:2a::1                                  0.626ms
 3:  fdc8:dc88:ee11:193::1                                 1.522ms
 4:  fdc8:dc88:ee11:197::1                               132.102ms asymm  3
 5:  fd28:7515:7d51:a::1                                 153.749ms reached

ping -c5 fd28:7515:7d51:a::1
PING fd28:7515:7d51:a::1(fd28:7515:7d51:a::1) 56 data bytes
64 bytes from fd28:7515:7d51:a::1: icmp_seq=1 ttl=61 time=153 ms
64 bytes from fd28:7515:7d51:a::1: icmp_seq=2 ttl=61 time=154 ms
64 bytes from fd28:7515:7d51:a::1: icmp_seq=3 ttl=61 time=153 ms
64 bytes from fd28:7515:7d51:a::1: icmp_seq=4 ttl=61 time=154 ms
64 bytes from fd28:7515:7d51:a::1: icmp_seq=5 ttl=61 time=153 ms

--- fd28:7515:7d51:a::1 ping statistics ---
5 packets transmitted, 5 received, 0% packet loss, time 4006ms
rtt min/avg/max/mdev = 152.951/153.448/153.995/0.390 msi

mtr -rc10 fd28:7515:7d51:a::1
Start: 2024-07-16T21:47:39+0000
HOST: shell-lax                   Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- fd42:4242:2601:1018::1     0.0%    10    0.3   0.4   0.3   0.5   0.1
  2.|-- tier1.us-lax1.burble.dn42  0.0%    10    1.0   0.9   0.8   1.1   0.1
  3.|-- LosAngeles1.ca.us.sun.dn4  0.0%    10    2.1   2.0   1.8   2.3   0.2
  4.|-- London1.uk.sun.dn42        0.0%    10  132.3 132.8 132.1 134.5   0.7
  5.|-- fd28:7515:7d51:a::1        0.0%    10  157.2 154.1 153.4 157.2   1.1
```

* to generate traffic with `iperf3`
```bash-session
ssh hcartiaux@shell.fr.burble.dn42 iperf3 -s &
iperf3 -c shell.fr.burble.dn42
Connecting to host shell.fr.burble.dn42, port 5201
[  5] local fd28:7515:7d51:a::1 port 49198 connected to fd42:4242:2601:1016:216:3eff:fe01:2f1f port 5201
[ ID] Interval           Transfer     Bitrate         Retr  Cwnd
[  5]   0.00-1.00   sec  2.50 MBytes  20.9 Mbits/sec    0    269 KBytes
[  5]   1.00-2.00   sec  3.12 MBytes  26.2 Mbits/sec    6    398 KBytes
[  5]   2.00-3.00   sec  4.00 MBytes  33.6 Mbits/sec    0    404 KBytes
[  5]   3.00-4.00   sec  2.00 MBytes  16.8 Mbits/sec    0    408 KBytes
[  5]   4.00-5.00   sec  3.50 MBytes  29.4 Mbits/sec    0    413 KBytes
[  5]   5.00-6.00   sec  3.25 MBytes  27.3 Mbits/sec    0    433 KBytes
[  5]   6.00-7.00   sec  4.38 MBytes  36.7 Mbits/sec    0    467 KBytes
[  5]   7.00-8.00   sec  5.12 MBytes  43.0 Mbits/sec    0    516 KBytes
[  5]   8.00-9.00   sec  5.12 MBytes  43.0 Mbits/sec    0    584 KBytes
[  5]   9.00-10.00  sec  5.12 MBytes  43.0 Mbits/sec    0    673 KBytes
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.00  sec  38.1 MBytes  32.0 Mbits/sec    6             sender
[  5]   0.00-10.12  sec  37.1 MBytes  30.7 Mbits/sec                  receiver

iperf Done.
```

## Follow-up

We are officially connected to dn42!
The next post will describe how I've segmented my network using an [IGP](https://en.wikipedia.org/wiki/Interior_gateway_protocol) and set-up redundant routes with more peers!
