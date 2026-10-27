# LAB-050 — Solution

## Summary

Educational intent: take the W2 corporate WAN and add two tenants that share nothing with it but the physical Internet underlay: MGMT (management, HQ stub to HQ-WAN1 to BR1, BR2 and BR1-ACC1) and OT (BR1 warehouse segment to the HQ OT servers). The student builds VRFs on four routers, protected GRE tunnels that live in a VRF while their transport stays in the global table, per-VRF OSPF over them, VRF-aware SSH access control, and opens the headend filter for the new /29 loopback pairs. Verification is a reachability matrix, a capture (the provider sees only ESP and IKE between three address pairs) and a cable-pull test.

Blueprint mapping (X/N lab, no faults): 2.2.a (VRF, tenant routing tables and per-VRF services), 2.2.b (protected tunnels, VRF-aware tunnel interface with global transport), 3.2.b (per-VRF OSPF, areas and the interaction with the provider /16 redistribution). Proven platform behaviour: a protected GRE tunnel with `vrf forwarding` on the tunnel and a global loopback source works on iol-xe 17.16; several protected tunnels with different loopbacks (and two tunnels with the same loopback and different destinations) share one IKEv2 profile and wildcard keyring, each with its own SA; no `tunnel key` or `shared` fallback is needed.

## Intentional Faults

None (X/N lab). Expected student errors, for the debrief:

| Error | Symptom | Where it shows |
|---|---|---|
| `vrf forwarding` entered after `ip address` | IP address wiped (`% Interface ... IPv4 disabled and address(es) removed`), interface has no address | `show ip interface brief`, `show ip vrf interfaces` |
| `ip ospf 1 area N` left on a moved interface | OSPF 1 keeps the interface only if it is still in the global table; moving it removes it from the process and from the passive list, a later re-add puts a second process on it | `show ip ospf interface brief` |
| OSPF process not bound to the VRF (`router ospf N` instead of `router ospf N vrf X`) | process runs in the global table, no neighbour on the VRF tunnel | `show ip ospf neighbor` empty on the tunnel |
| VRF OSPF process without a router-id | a VRF OSPF process takes its router-id from the up, addressed interfaces of that VRF (highest loopback, else highest other); it starts once any interface in the VRF is addressed, and `%OSPF-4-NORTRID` appears only if none is up and addressed when the process is configured | `%OSPF-4-NORTRID` (derived, not captured) |
| VTY access class without `vrf-also` | SSH from the stub (source Loopback99 in VRF MGMT) refused: `% Connection refused by remote host` | telnet-to-22 test, `show ip access-lists WAN-MGMT` counters |
| Stub SSH sourced from the /31 link | refused although `vrf-also` is set: 10.10.254.10 is not in WAN-MGMT | needs `ip ssh source-interface Loopback99` |
| WAN1-INET-IN without the /29 pairs | tunnels up/down, IKEv2 SAs missing, `deny ip any any log` counter rising and `%SEC-6-IPACCESSLOGP` entries | `show ip access-lists WAN1-INET-IN` |
| `ip nat inside` left on e0/2.99 or e0/2.40 | tenant subnet could be translated out of the Internet interface (no NAT rule matches in the VRF, but the interface keeps a role it should not have) | `show running-config interface` (not captured) |
| Test without `vrf` | ping/traceroute from the global table looks at the wrong table (Q4) | `ping 10.21.40.102` on HQ-WAN1 fails while `ping vrf OT ...` works |

## Diagnosis / Methodology

No faults. The method for a student who finds a tenant tunnel down or a tenant route missing:

1. Underlay first, in the global table: `ping 203.0.113.153 source Loopback201` (WAN1) must work (allowed by the new ICMP ACEs); if not, `show ip access-lists WAN1-INET-IN` (deny counters) and `show crypto ikev2 sa` (no SA).
2. Crypto: `show crypto ikev2 sa` shows the SA per loopback pair with `none/MGMT` or `none/OT` (the VRF the tunnel is in); `show crypto session` shows UP-ACTIVE per tunnel interface.
3. Tunnel: `show interfaces TunnelN` (transport source/destination; the VRF is on the tunnel interface, the transport lookup stays in the global table), `show ip vrf interfaces`.
4. Routing: `show ip ospf neighbor` (the VRF processes are separate: `show ip ospf 99 neighbor`), then `show ip route vrf X`. Wrong-cause traps: the global table may hold a path that looks right (BR1 `show ip route 10.21.99.1` gives `10.21.0.0/16 ... via Tunnel21`, the provider /16 redistribution, which cannot deliver into VRF MGMT); only `show ip route vrf MGMT 10.21.99.1` (connected Et0/2.99) is the truth.
5. Reachability tests always with `vrf X` and an explicit source (`ping vrf MGMT 10.21.99.1 source Loopback99`), then from the hosts for the user view.

## Solution Configuration

Applied in this order (the same script was tested on two separate imports; BR1-ACC1, hosts, PROV-* and the global WAN are unchanged). `vrf forwarding` removes the address, so each interface is re-addressed after it. The same final configs are the W3 stage (`environments/WAN/README.md`).

### HQ-CORE1

```
vrf definition MGMT
 rd 65010:99
 address-family ipv4
 exit-address-family
interface Loopback99
 no ip ospf 1 area 0
 vrf forwarding MGMT
 ip address 10.10.99.2 255.255.255.0
 ip ospf network point-to-point
 ip ospf 99 area 0
interface Ethernet1/0.99
 description to HQ-WAN1 Ethernet0/2.99 (MGMT)
 encapsulation dot1Q 99
 vrf forwarding MGMT
 ip address 10.10.254.10 255.255.255.254
 ip ospf network point-to-point
 ip ospf dead-interval 4
 ip ospf hello-interval 1
 ip ospf cost 10
 ip ospf 99 area 0
router ospf 99 vrf MGMT
 router-id 10.255.10.1
 passive-interface Loopback99
ip ssh source-interface Loopback99
```

### HQ-WAN1

```
vrf definition MGMT
 rd 65010:99
 address-family ipv4
 exit-address-family
vrf definition OT
 rd 65010:40
 address-family ipv4
 exit-address-family
interface Loopback40
 no ip ospf 1 area 0
 vrf forwarding OT
 ip address 10.10.40.1 255.255.255.0
 ip ospf network point-to-point
 ip ospf 40 area 0
interface Ethernet0/2.99
 description to HQ-CORE1 Ethernet1/0.99 (MGMT)
 encapsulation dot1Q 99
 vrf forwarding MGMT
 ip address 10.10.254.11 255.255.255.254
 ip ospf network point-to-point
 ip ospf dead-interval 4
 ip ospf hello-interval 1
 ip ospf cost 10
 ip ospf 99 area 0
interface Tunnel91
 description to BR1-RTR1 Tunnel91 (MGMT)
 vrf forwarding MGMT
 ip address 10.250.91.1 255.255.255.0
 ip mtu 1400
 ip tcp adjust-mss 1360
 ip ospf network point-to-point
 ip ospf hello-interval 5
 ip ospf dead-interval 20
 ip ospf cost 100
 ip ospf 99 area 0
 tunnel source Loopback201
 tunnel mode gre ip
 tunnel destination 203.0.113.153
 tunnel protection ipsec profile VPN-PROF
interface Tunnel92
 description to BR2-RTR1 Tunnel92 (MGMT)
 vrf forwarding MGMT
 ip address 10.250.92.1 255.255.255.0
 ip mtu 1400
 ip tcp adjust-mss 1360
 ip ospf network point-to-point
 ip ospf hello-interval 5
 ip ospf dead-interval 20
 ip ospf cost 100
 ip ospf 99 area 0
 tunnel source Loopback201
 tunnel mode gre ip
 tunnel destination 203.0.113.161
 tunnel protection ipsec profile VPN-PROF
interface Tunnel41
 description to BR1-RTR1 Tunnel41 (OT)
 vrf forwarding OT
 ip address 10.250.41.1 255.255.255.0
 ip mtu 1400
 ip tcp adjust-mss 1360
 ip ospf network point-to-point
 ip ospf hello-interval 5
 ip ospf dead-interval 20
 ip ospf cost 100
 ip ospf 40 area 0
 tunnel source Loopback202
 tunnel mode gre ip
 tunnel destination 203.0.113.154
 tunnel protection ipsec profile VPN-PROF
router ospf 99 vrf MGMT
 router-id 10.255.10.41
router ospf 40 vrf OT
 router-id 10.255.10.41
 passive-interface Loopback40
ip access-list extended WAN1-INET-IN
 no 220
 permit udp 203.0.113.152 0.0.0.7 203.0.113.144 0.0.0.7 eq isakmp
 permit udp 203.0.113.152 0.0.0.7 203.0.113.144 0.0.0.7 eq non500-isakmp
 permit esp 203.0.113.152 0.0.0.7 203.0.113.144 0.0.0.7
 permit udp 203.0.113.160 0.0.0.7 203.0.113.144 0.0.0.7 eq isakmp
 permit udp 203.0.113.160 0.0.0.7 203.0.113.144 0.0.0.7 eq non500-isakmp
 permit esp 203.0.113.160 0.0.0.7 203.0.113.144 0.0.0.7
 permit icmp 203.0.113.152 0.0.0.7 203.0.113.144 0.0.0.7 echo
 permit icmp 203.0.113.152 0.0.0.7 203.0.113.144 0.0.0.7 echo-reply
 permit icmp 203.0.113.160 0.0.0.7 203.0.113.144 0.0.0.7 echo
 permit icmp 203.0.113.160 0.0.0.7 203.0.113.144 0.0.0.7 echo-reply
 deny ip any any log
line vty 0 4
 access-class WAN-MGMT in vrf-also
```

### BR1-RTR1

```
vrf definition MGMT
 rd 65010:99
 address-family ipv4
 exit-address-family
vrf definition OT
 rd 65010:40
 address-family ipv4
 exit-address-family
interface Ethernet0/2.99
 no ip ospf 1 area 21
 no ip nat inside
 vrf forwarding MGMT
 ip address 10.21.99.1 255.255.255.0
 ip ospf 99 area 0
interface Ethernet0/2.40
 no ip ospf 1 area 21
 no ip nat inside
 vrf forwarding OT
 ip address 10.21.40.1 255.255.255.0
 ip ospf 40 area 0
interface Tunnel91
 description to HQ-WAN1 Tunnel91 (MGMT)
 vrf forwarding MGMT
 ip address 10.250.91.21 255.255.255.0
 ip mtu 1400
 ip tcp adjust-mss 1360
 ip ospf network point-to-point
 ip ospf hello-interval 5
 ip ospf dead-interval 20
 ip ospf cost 100
 ip ospf 99 area 0
 tunnel source Loopback201
 tunnel mode gre ip
 tunnel destination 203.0.113.145
 tunnel protection ipsec profile VPN-PROF
interface Tunnel41
 description to HQ-WAN1 Tunnel41 (OT)
 vrf forwarding OT
 ip address 10.250.41.21 255.255.255.0
 ip mtu 1400
 ip tcp adjust-mss 1360
 ip ospf network point-to-point
 ip ospf hello-interval 5
 ip ospf dead-interval 20
 ip ospf cost 100
 ip ospf 40 area 0
 tunnel source Loopback202
 tunnel mode gre ip
 tunnel destination 203.0.113.146
 tunnel protection ipsec profile VPN-PROF
router ospf 99 vrf MGMT
 router-id 10.255.21.1
 passive-interface Ethernet0/2.99
router ospf 40 vrf OT
 router-id 10.255.21.1
 passive-interface Ethernet0/2.40
line vty 0 4
 access-class WAN-MGMT in vrf-also
```

### BR2-RTR1

```
vrf definition MGMT
 rd 65010:99
 address-family ipv4
 exit-address-family
interface Loopback99
 no ip ospf 1 area 22
 vrf forwarding MGMT
 ip address 10.22.99.1 255.255.255.255
 ip ospf 99 area 0
interface Tunnel92
 description to HQ-WAN1 Tunnel92 (MGMT)
 vrf forwarding MGMT
 ip address 10.250.92.22 255.255.255.0
 ip mtu 1400
 ip tcp adjust-mss 1360
 ip ospf network point-to-point
 ip ospf hello-interval 5
 ip ospf dead-interval 20
 ip ospf cost 100
 ip ospf 99 area 0
 tunnel source Loopback201
 tunnel mode gre ip
 tunnel destination 203.0.113.145
 tunnel protection ipsec profile VPN-PROF
router ospf 99 vrf MGMT
 router-id 10.255.22.1
 passive-interface Loopback99
line vty 0 4
 access-class WAN-MGMT in vrf-also
```

## Verification

Note: the first pings right after applying the solution or after a tunnel event can be briefly lossy (ARP and Tunnel adjacencies settling; seen once as 0/2 and 1/2 in one test run, 100% on retest). Wait a few seconds and repeat the test before suspecting a fault.

Captured on a fresh import after applying the solution (trimmed).

HQ-WAN1 neighbours, IKEv2 sessions and tunnels (V1, V8: the two global tunnels and two original IKE sessions are unchanged, the three tenant tunnels add three SAs; Tunnel91 and Tunnel92 share Lo201 as source with different destinations):

```
show ip ospf neighbor | include FULL|Neighbor
Neighbor ID     Pri   State           Dead Time   Address         Interface
10.255.10.1       0   FULL/  -        00:00:03    10.10.255.96    Ethernet0/2
10.255.21.1       0   FULL/  -        00:00:16    10.250.21.21    Tunnel21
10.255.22.1       0   FULL/  -        00:00:17    10.250.22.22    Tunnel22
10.255.22.1       0   FULL/  -        00:00:17    10.250.92.22    Tunnel92
10.255.21.1       0   FULL/  -        00:00:18    10.250.91.21    Tunnel91
10.255.10.1       0   FULL/  -        00:00:03    10.10.254.10    Ethernet0/2.99
10.255.21.1       0   FULL/  -        00:00:18    10.250.41.21    Tunnel41
show crypto ikev2 sa | include READY|DOWN
3         203.0.113.129/500     203.0.113.131/500     none/none            READY  
1         203.0.113.145/500     203.0.113.153/500     none/MGMT            READY  
2         203.0.113.129/500     203.0.113.133/500     none/none            READY  
5         203.0.113.145/500     203.0.113.161/500     none/MGMT            READY  
4         203.0.113.146/500     203.0.113.154/500     none/OT              READY
```

Tenant routing tables (V1, V7):

```
show ip route vrf MGMT ospf | include ^O|^ *10
      10.0.0.0/8 is variably subnetted, 9 subnets, 3 masks

O        10.10.99.0/24 [110/11] via 10.10.254.10, 00:01:17, Ethernet0/2.99
O        10.21.99.0/24 [110/110] via 10.250.91.21, 00:01:09, Tunnel91
O        10.22.99.1/32 [110/101] via 10.250.92.22, 00:01:04, Tunnel92
show ip route vrf OT | include ^[OCL]
Codes: L - local, C - connected, S - static, R - RIP, M - mobile, B - BGP
C        10.10.40.0/24 is directly connected, Loopback40
L        10.10.40.1/32 is directly connected, Loopback40

O        10.21.40.0/24 [110/110] via 10.250.41.21, 00:01:09, Tunnel41

C        10.250.41.0/24 is directly connected, Tunnel41
L        10.250.41.1/32 is directly connected, Tunnel41
```

BR1-RTR1 per-VRF and global tables (V1, V7, V8):

```
show ip route vrf MGMT | include ^[OCLS]
Codes: L - local, C - connected, S - static, R - RIP, M - mobile, B - BGP
O        10.10.99.0/24 [110/111] via 10.250.91.1, 00:01:09, Tunnel91
O        10.10.254.10/31 [110/110] via 10.250.91.1, 00:01:09, Tunnel91
C        10.21.99.0/24 is directly connected, Ethernet0/2.99
L        10.21.99.1/32 is directly connected, Ethernet0/2.99
O        10.22.99.1/32 [110/201] via 10.250.91.1, 00:01:06, Tunnel91
C        10.250.91.0/24 is directly connected, Tunnel91
L        10.250.91.21/32 is directly connected, Tunnel91
O        10.250.92.0/24 [110/200] via 10.250.91.1, 00:01:06, Tunnel91
show ip route vrf OT | include ^[OCLS]
Codes: L - local, C - connected, S - static, R - RIP, M - mobile, B - BGP
O        10.10.40.0/24 [110/101] via 10.250.41.1, 00:01:09, Tunnel41
C        10.21.40.0/24 is directly connected, Ethernet0/2.40
L        10.21.40.1/32 is directly connected, Ethernet0/2.40
C        10.250.41.0/24 is directly connected, Tunnel41
L        10.250.41.21/32 is directly connected, Tunnel41
```

Matrix (replies out of 2 pings; run with the solution applied, hosts `ping -c 2 -W 2`):

| Source | MGMT addresses (10.21.99.1/.11, 10.22.99.1, 10.10.99.2) | OT (10.21.40.1, 10.21.40.102, 10.10.40.1) | Corporate hosts (10.10.10.101, 10.22.10.101, 10.21.10.101) | Internet 198.51.100.200 |
|---|---|---|---|---|
| BR1-PC1 (users) | 0 | 0 | 2 | 2 |
| BR1-PC2 (OT) | 0 | 10.10.40.1 = 2, 10.21.40.1 = 2 | 0 | 0 |
| BR2-PC1 | 0 | 0 | 2 | 2 |
| HQ-PC1 | 0 | 0 | 2 (BR1, BR2) | 0 (no Internet for HQ users: W2 baseline, no PAT at the stub) |
| HQ management (stub `ping vrf MGMT ... source Loopback99`) | 10.21.99.1, 10.21.99.11, 10.22.99.1: 100% | 0% (not in the table) | - | - |

Per-tenant tests: WAN1 `ping vrf OT 10.21.40.102 source Loopback40` 100%; `ping vrf OT 10.21.99.1` 0%; global `ping 10.21.40.102` on WAN1 0% (Q4). BR1 `ping vrf MGMT 10.10.99.2 source Ethernet0/2.99` 100%, `ping vrf OT 10.10.40.1 source Ethernet0/2.40` 100%.

SSH (V4; no password dialog is possible in the console tool, so the acceptance is proven with a TCP connection to port 22 from the VRF with a chosen source): from the stub, `telnet <ip> 22 /vrf MGMT /source-interface Loopback99` gives `Open` and `SSH-2.0-Cisco-1.25` for BR1 10.21.99.1, BR1-ACC1 10.21.99.11 and BR2 10.22.99.1; with source Ethernet1/0.99 (10.10.254.10, not in WAN-MGMT) `% Connection refused by remote host`; BR2 with `access-class WAN-MGMT in` (no `vrf-also`) refuses the same source, restored with `vrf-also` accepts. Users have no route to any management address.

MTU (V6): `ping vrf MGMT 10.10.99.2 size 1400 df-bit` 2/2, size 1401 0/2; `Tunnel transport MTU 1414`, `Tunnel source 203.0.113.153 (Loopback201), destination 203.0.113.145`.

Capture on the BR1-INET1 link, 60 s with Tunnel41 bounced and pings running (V5; REST capture API, `PUT /labs/{lab}/links/{link}/capture/start`, then `GET /api/v0/pcap/{link_id}`):

```
  20  203.0.113.129 > 203.0.113.131  ESP        (Tunnel21, both directions) + udp 123>123 NTP
  15  203.0.113.145 > 203.0.113.153  ESP   / 15 reverse     (Tunnel91, Lo201 <-> Lo201)
  27  203.0.113.146 > 203.0.113.154  ESP   / 26 reverse     (Tunnel41, Lo202 <-> Lo202)
   4  203.0.113.146 > 203.0.113.154  udp 500>500  / 4 reverse (IKE during the Tunnel41 bounce)
IKE exchange types seen: [34, 35, 37]
```

No protocol 47 (GRE), no inner addresses, no VRF identifiers.

NTP: BR2 `*~203.0.113.129 st 3 reach 377` (global table unaffected). BR1-ACC1's NTP server 203.0.113.129 is unreachable once its gateway is in VRF MGMT (`st 16 reach 0`): expected, a debrief point (management NTP would come from the HQ management network), not a check target.

## Failure / Recovery Behaviour

Method: cable pull of BR1's Internet link = `shutdown` on BR1-RTR1 e0/0 and on PROV-INET1 e0/1 (provider port, about 0.6 s later; both ends). T0 = the INET1 admin-down log stamp; times from the HQ-WAN1 log (msec) minus T0 on one host clock; corporate loss = BR1-PC1 ping to HQ-PC1 at 1/s. Restore: `no shutdown` both ends, T0 = INET1 link-up stamp. Raw values (s):

| Run | T0 pull | OSPF dead T91/T41/T21 | line down T91/T41/T21 | corporate pings lost |
|---|---|---|---|---|
| 1 | 03:13:00.905 | 13.4 / 12.5 / 17.2 | 16.8 / 18.9 / 23.5 | 20 |
| 2 | 03:16:18.184 | 13.2 / 16.5 / 14.9 | 17.8 / 20.8 / 19.3 | 17 |
| 3 | 03:20:02.746 | 12.6 / 17.0 / 15.7 | 19.2 / 23.8 / 19.7 | 18 |

| Run | T0 restore | line up T21/T91/T41 | OSPF FULL T21/T41/T91 | all 3 BR1 tunnels FULL |
|---|---|---|---|---|
| 1 | 03:14:05.974 | 4.3 / 8.4 / 11.5 | 9.0 / 11.5 / 13.1 | 13.1 |
| 2 | 03:17:32.195 | 9.3 / 5.8 / 4.8 | 9.3 / 9.7 / 10.4 | 10.4 |
| 3 | 03:20:57.193 | 7.6 / 20.4 / 23.5 | 7.6 / 23.5 / 20.4 | 23.5 |

| Scenario (trigger, end condition) | Runs | Documented range | Basis |
|---|---|---|---|
| Cable pull of BR1's Internet link; end = OSPF dead on each BR1 tunnel at HQ-WAN1 | 12.5-17.2 s | 12-18 s | hello 5 / dead 20: 15-20 s after the last hello, minus the phase of the last hello |
| Same trigger; end = tunnel line protocol down | 16.8-23.8 s | 16-25 s | IKEv2 DPD (10 s, then on-demand retries) |
| Same trigger; end = corporate BR1-PC1 to HQ-PC1 ping works again (lost pings at 1/s) | 17-20 pings | 17-21 s | provider /16 statics take over once the tunnel /24s age out (Tunnel21 dead 20 s) |
| `no shutdown` both ends; end = all three BR1 tunnels FULL | 10.4-23.5 s (later runs after a few minutes' outage: 17.0-55.5 s) | 10-25 s after a short outage; 30-60 s after an outage of a few minutes (allow about 60 s) | link up, IKE negotiation, OSPF hello/dead 5/20; during a long outage the IKEv2 IKE_SA_INIT retransmits back off (2 s, then growing) and a timed-out tunnel only restarts on the next initiation, so Tunnel21 is usually last |

Observations. During the outage corporate BR1-PC1 to HQ-PC1 works on the provider /16 (BR1 `10.10.0.0/16 static via 100.64.21.0`; HQ-WAN1 `10.21.0.0/16 static via 100.64.10.0`). Stub `ping vrf MGMT 10.21.99.1` 0/2, WAN1 `ping vrf OT 10.21.40.102` 0/2, BR1-PC2 to 10.10.40.1 100% loss, `show ip route vrf MGMT 10.10.99.2` on BR1 `% Subnet not in table`: MGMT and OT to BR1 have no backup by design. BR2's tunnels (22, 92) stay FULL. As in LAB-048, after some restores Tunnel21 flaps once (run 2: 8 s after FULL, 0.03 s down) and one run saw a second `Tunnel91 LOADING to FULL`; both settle without intervention.

## Answers to Analysis Questions

**Q1.** `show ip route vrf X <addr>` vs `show ip route <addr>` (compare BR1 for 10.21.99.1: global `10.21.0.0/16 ... via Tunnel21`, VRF MGMT `connected Ethernet0/2.99`), `show ip vrf interfaces` and `show ip vrf` (which interface is in which table), `show crypto ikev2 sa` (the `none/MGMT` column is the tunnel's VRF), `show interfaces TunnelN` (tunnel transport source/destination, resolved in the global table), `ping vrf X ... source`.

**Q2.** IPsec protection selects the SA by tunnel endpoints (and, for a shared profile, by the transport pair): two protected tunnels with the same source and destination would map to one SA and the router could not tell which tunnel an ESP packet belongs to. Here every tunnel has its own address pair (the per-VRF tunnels use Lo201 and Lo202 from the provider /29s; Tunnel91 and Tunnel92 share Lo201 on HQ-WAN1 but have different destinations). If the endpoints had to be shared, `tunnel key` per tenant (GRE key) plus `tunnel protection ipsec profile VPN-PROF shared` would be needed (not needed and not tested here).

**Q3.** Three address pairs with ESP of various sizes and counts, IKE (UDP 500, exchange types 34/35/37) when an SA is re-keyed or created, and the corporate pair 129/131. No GRE (it is inside ESP), no inner addresses, no VRF names: it cannot tell how many tenants exist, only that there are three encrypted flows (traffic analysis on sizes and timing remains possible).

**Q4.** A ping without `vrf` uses the global table (and the global source address): it tests another network. In this design a global ping to a tenant address either fails although the tenant works, or succeeds through the provider /16 corporate path although the tenant would not (HQ-WAN1 global `ping 10.21.40.102` fails while `ping vrf OT 10.21.40.102` succeeds); a ping from the wrong source can also pass or fail the VTY/WAN-MGMT access list.

**Q5.** A VRF is the SD-WAN segment (VPN ID): per-VRF routing tables on every edge, transport that carries all segments over shared tunnels with a segment label (IPsec SAs or GRE key per segment here; SD-WAN uses one set of data-plane tunnels per transport and a VPN label), the control plane (OMP) advertising per-VPN routes instead of a per-VRF OSPF process, and policy deciding which segments reach which sites. Here the tenant separation is built by hand per tunnel; in SD-WAN it is a property of the fabric.

**Q6.** MGMT and OT to BR1 have no backup: their tunnels ride only BR1's Internet link and no provider-service path exists inside the VRFs (the provider service is a global-table /16 static pair and cannot deliver into a VRF). The corporate tenant fails over because the global table carries the provider /16 statics (redistributed on HQ-WAN1), which longest match prefers only after the tunnel's /24s are gone.

**Q7.** NTP: BR1-ACC1's configured server (203.0.113.129) is in the global table and is no longer reachable from VRF MGMT, so it shows `st 16 reach 0`. To restore time the switch needs an NTP source reachable inside MGMT, configured with the VRF (`ntp server vrf MGMT <address>`). Precondition: the switch has no VRF in this lab, so `vrf definition MGMT` must exist on it and Vlan99 must be in it (`vrf forwarding MGMT`) first; without the VRF the command is rejected (`% IP routing table MGMT does not exist`), and while Vlan99 stays in the global table the VRF server is accepted but unreachable (`st 16 reach 0`). Alternatively the NTP server must be reachable through the switch's global table. The server can be, for example, a server on the HQ management network, as MS-3 CR2 does with `ntp server vrf MGMT 10.50.50.1`. This lab provides no such server, so restoring it is a debrief point and not a check target.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a) |
