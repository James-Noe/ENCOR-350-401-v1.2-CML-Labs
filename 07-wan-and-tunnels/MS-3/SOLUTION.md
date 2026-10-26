# MS-3 — Solution

## Summary

Closes module 07 on one network: the lite HQ campus (H3 lite, 6 nodes), the data centre (DC min, 2), the edge (E3 min, 2), the WAN (W4 with BR1 collapsed, 7) and a cabled but unconfigured BR3 (1): 18 nodes. Three change requests (CR1 onboard BR3 behind a carrier PAT, CR2 AAA and time over MGMT, CR3 eBGP replacing static provider routing) and three multi-cause tickets (TK1 OPS cannot reach the branches, TK2 voice and the NOC's path complaint, TK3 BR2 SSH from MGMT) are worked inside one 240-minute window.

Blueprint mapping (instructor only): 2.2.a (VRF-lite, MGMT), 2.2.b (GRE/IPsec site-to-site, NAT-T), 3.1.a (802.1Q allowed-VLAN list, found through the STP path, 3.1.c), 3.2.b (OSPF filtering, ABR), 3.2.c (eBGP CE–PE), 3.2.d (policy routing with tracking), 3.3.b (NAT/PAT), 4.1 (logs, EEM evidence), 4.4 (IP SLA), 1.4 (QoS: shaping and queuing, F5 and TK2), 5.1.b (AAA), 5.2.a (VTY access control).

**Build notes:**
- Tunnel mode fails across BR3's PAT (`Failed to find a matching policy`, line protocol down). Tunnel23 and BR3's MGMT tunnel Tunnel93 use the transport-mode profile `VPN-PROF-NAT` at both ends (as in LAB-053). LAB.md does not say which mode: the student finds it.
- INET1's PAT uses `ip nat inside source list BR3-PAT interface Loopback136 overload` (Loopback136 203.0.113.136/32); a one-address pool on a subnet address never translates and `prefix-length 32` is rejected.
- HQ-WAN1 does **not** originate the type-3 for 10.10.20.0/24 under the inbound `distribute-list`. In TK1's evidence the branches have no route (only their default to INET1) and HQ-WAN1 has none either.
- PE1 BGP is pre-staged (AS 64700, per-customer inbound prefix-lists, statics at AD 200); BR3 has Loopback10 (users stand-in), Loopback99 (student-built, VRF MGMT) and Tunnel93; the background job is UDP 3 Mb/s (a default-window TCP upload reached only 1.7 Mb/s and produced no symptom); V3 needs a failover allowance (25 s) because the provider-link failure is detected by an IP SLA (frequency 5 s, timeout 1 s, delay down 5 s).

## Intentional Faults

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-WAN1 | `router ospf 1` has `distribute-list prefix HQ-IN in Ethernet0/2`; `HQ-IN` is `seq 5 deny 10.10.16.0/20 le 32`, `seq 10 permit 0.0.0.0/0 le 32`. The /20 covers VLAN 20 (10.10.20.0/24) | HQ-WAN1 has no RIB route to VLAN 20 and (as built) does not originate the type-3 into areas 21–23: the branches have no route to 10.10.20.0/24; OPS users lose the branches (TK1). VLAN 10 is unaffected |
| F2 | HQ-ACC1 | VLAN 20 removed from the allowed list of e0/0 (`switchport trunk allowed vlan 10,99`) | None at boot (VLAN 20 forwards on e0/1 to DIST2, the VLAN 20 root); the loss of ACC1–DIST2 cuts OPS off completely (V7); latent. Fixing F2 alone leaves TK1 unchanged |
| F3 | BR1-RTR1 | IP SLA 30 targets 100.64.10.0 (PE1's side) instead of 100.64.10.1 (HQ-WAN1) | Latent: track 30 stays Up when the provider path fails beyond PE1, so voice is black-holed in the V3 drill |
| F4 | BR1-RTR1 | `ip policy route-map VOICE-PBR` on e0/2 (parent) instead of e0/2.10 | Voice is never policy-routed (`Policy routing matches: 0`), follows the tunnel (TK2 part 1) |
| F5 | BR1-RTR1 | `service-policy output WAN-SHAPE` on e0/1 (provider port) instead of e0/0 (Internet port) | No shaping/queuing on the 2 Mb/s Internet circuit: voice in the tunnel is dropped with the backup job (TK2 part 2) |
| F6 | BR2-RTR1 | Tunnel92 (MGMT tunnel) has `vrf forwarding OT` | IOS drops `ip ospf 99 area 0` at boot (process 99 is in VRF MGMT): no OSPF 99 adjacency, BR2 unreachable from MGMT (TK3 part 1) |
| F7 | BR2-RTR1 | `access-class WAN-MGMT in` without `vrf-also` on `line vty 0 4` | With F6 fixed, SSH from MGMT is refused before authentication (TK3 part 2) |

Fault logic: TK1 = F1 (F2 latent, found by V7 or by checking VLAN 20's path); TK2 = F4 and F5 in series for the ticket, F3 latent until the V3 drill; TK3 = F6 hides F7. Interactions: CR2's RADIUS on BR2 cannot be verified until TK3 is fixed; CR3 must not renumber the provider links (V5/V3). Wrong-fix traps: a static route for 10.10.20.0/24 on HQ-WAN1 (masks F1, breaks V1's dynamic-routing rule); raising BR1's tunnel bandwidth or touching the provider conditioning; `transport input all` or removing the access class on BR2 (V4). Red herrings: BR1's EEM tunnel-down evidence is a consequence of F5 (see below), the 0.2 % loss on the BR1 Internet circuit is present without bulk, BR3's onboarding is blamed for TK3, DC-AAA1 looks suspect for TK3.

## Diagnosis / Methodology

**TK1.** (1) Scope: HQ-PC2 (VLAN 20) pings 10.10.20.1, the Internet host 192.0.2.200, but not 10.21.10.101 / 10.22.10.101; HQ-PC1 (VLAN 10) reaches the branches. So L2 delivery of VLAN 20, the gateway and the tunnels are fine (tunnels, OSPF FULL and 5 IKEv2 SAs READY). (2) From a branch: `show ip route 10.10.20.0` on BR2 is `% Subnet not in table` (only the default to INET1 exists), so the return path and the route are the problem; replies go to INET1 and die. (3) At HQ-WAN1: `show ip route 10.10.20.0` is `% Subnet not in table`; the LSA is in the database (CORE1's type-1 lists 10.10.20.0/24) and `show ip protocols | include filtered` shows `Ethernet0/2 filtered by (prefix-list) HQ-IN`; `show ip prefix-list HQ-IN` shows the /20 deny. Cause: **F1**. Debrief: the old test range 10.10.16.0/22 needed a /22; the /20 caught a live VLAN. (4) `show ip ospf database summary 10.10.20.0` on HQ-WAN1 is empty, which is why branches lose the route and why a traceroute from a branch ends at its own provider next hop. (5) Plausible but wrong: the access layer (VLAN 20 reaches CORE1, VIP answers), the VRRP gateway (CORE1 master), the tunnels (VLAN 10 uses them). A static route on HQ-WAN1 is the trap. (6) **F2** is found when the student checks VLAN 20's path (`show interfaces trunk` on ACC1 lists Et0/0 without VLAN 20 while DIST1 e0/2 allows it; `show spanning-tree vlan 20` on ACC1 has only Et0/1 forwarding) or by V7 (ACC1–DIST2 cable pull cuts OPS). F2 alone fixed: TK1 unchanged.

**TK2.** (1) Scope: a host-side voice test (`iperf -u -S 0xB8`) under the backup job loses roughly 30-70 % (31 % in a 19 s re-measurement; it depends on the test length and queue state); the same stream with the job stopped is clean. (2) Where does voice go: `traceroute -t 184` from BR1-PC1 to HQ-PC1 goes 10.21.10.1, 10.250.21.1 (the tunnel); `show route-map VOICE-PBR` on BR1 has `matches: 0`; `show run interface Ethernet0/2.10` has no policy and `Ethernet0/2` has it: **F4**. (3) Queuing: `show policy-map interface Ethernet0/0` is empty while Ethernet0/1 shows WAN-SHAPE counters: **F5**. (4) Order of effects: F5 alone fixed gives 0.19 % loss for the stream (conditioning) but still on the tunnel ("queued correctly, still on the Internet path": the NOC part of TK2 stays open); F4 alone gives the provider line, 0/3753 lost, `Policy routing matches: 3759`. (5) **F3** is only found by the V3 drill (silent failure of HQ-WAN1–PE1): `show track 30` stays Up (PE1 answers), `show ip sla configuration 30` target 100.64.10.0; voice is black-holed. (6) The tunnel-down evidence files in BR1's RAM file system (`unix:`) are a consequence of F5: the unshaped job queues up to 5 s on the conditioned circuit and drops BR1's tunnel adjacencies on the dead timer; with F5 fixed the same 3 Mb/s job leaves ping at 72 ms and all three BR1 tunnels FULL.

**TK3.** (1) BR1 works with the same RADIUS server and tunnels, so AAA is not the cause (BR2 refuses before authentication). (2) `show ip ospf 99 neighbor` on HQ-WAN1 lacks BR2; on BR2 `show ip vrf interfaces` lists Tunnel92 in OT: **F6**. (3) After F6 the adjacency is up, but SSH from CORE1 (VRF MGMT, source 10.10.99.2) is `Connection refused` at once and `show access-lists WAN-MGMT` has no matches: **F7** (without `vrf-also` the access class refuses every session that arrives in a VRF before the ACL is evaluated). Wrong fixes: `transport input all` or removing the access class break V4.

## Solution Configuration

Order used in testing: faults first (they are independent), then CR1, CR3, CR2 (branches before HQ-WAN1). Commands are the tested scripts (config blocks have no `configure terminal`/`end`).

**TK1.** HQ-WAN1: `no ip prefix-list HQ-IN`, `ip prefix-list HQ-IN seq 5 deny 10.10.16.0/22 le 32`, `ip prefix-list HQ-IN seq 10 permit 0.0.0.0/0 le 32`. HQ-ACC1: `interface Ethernet0/0` / `switchport trunk allowed vlan add 20`.

**TK2.** BR1-RTR1:
```
no ip sla schedule 30
no ip sla 30
ip sla 30
 icmp-echo 100.64.10.1 source-interface Ethernet0/1
 threshold 1000
 timeout 1000
 frequency 5
ip sla schedule 30 life forever start-time now
interface Ethernet0/2
 no ip policy route-map VOICE-PBR
interface Ethernet0/2.10
 ip policy route-map VOICE-PBR
interface Ethernet0/1
 no service-policy output WAN-SHAPE
interface Ethernet0/0
 service-policy output WAN-SHAPE
```
(A running IP SLA cannot be modified: it is deleted and re-created.)

**TK3.** BR2-RTR1: `interface Tunnel92` / `vrf forwarding MGMT` (IOS removes the address: `% Interface Tunnel92 IPv4 disabled and address(es) removed due to disabling VRF MGMT`) / `ip address 10.250.92.22 255.255.255.0` / `ip ospf 99 area 0`; `line vty 0 4` / `access-class WAN-MGMT in vrf-also`.

**CR1 (BR3).** HQ-WAN1: four entries added at the top of `WAN1-INET-IN` (`permit udp host 203.0.113.136 host 203.0.113.129 eq isakmp` and `eq non500-isakmp`; the same two to 203.0.113.145), the transport-mode profile and the tunnels:
```
crypto ipsec transform-set TS-AES-TRANSPORT esp-aes 256 esp-sha256-hmac
 mode transport
crypto ipsec profile VPN-PROF-NAT
 set transform-set TS-AES-TRANSPORT
 set ikev2-profile IKEV2-PROF
interface Tunnel23
 description to BR3-RTR1 Tunnel23
 ip address 10.250.23.1 255.255.255.0
 ip mtu 1400
 ip tcp adjust-mss 1360
 ip ospf network point-to-point
 ip ospf hello-interval 5
 ip ospf dead-interval 20
 ip ospf cost 100
 ip ospf 1 area 23
 tunnel source Ethernet0/0
 tunnel mode gre ip
 tunnel destination 203.0.113.136
 tunnel protection ipsec profile VPN-PROF-NAT
interface Tunnel93
 vrf forwarding MGMT
 ip address 10.250.93.1 255.255.255.0
 (same MTU/MSS/OSPF 99 area 0 lines as Tunnel91)
 tunnel source Loopback201
 tunnel destination 203.0.113.136
 tunnel protection ipsec profile VPN-PROF-NAT
```
BR3-RTR1 (verbatim; the same text works on BR2 with its own addresses):
```
ip access-list standard WAN-MGMT
 permit 10.10.99.0 0.0.0.255
 permit 10.50.50.0 0.0.0.255
aaa new-model
aaa authentication login CON none
aaa authentication enable default enable none
aaa authentication login VTY local
aaa authorization exec VTY local
snmp-server group NMSGROUP v3 priv access WAN-MGMT
snmp-server user nmsuser NMSGROUP v3 auth sha AUTHPASS123 priv aes 128 PRIVPASS123
ntp authentication-key 1 hmac-sha2-256 NTPKEY123
ntp authenticate
ntp trusted-key 1
crypto ikev2 proposal PROP
 encryption aes-cbc-256
 integrity sha256
 group 14
crypto ikev2 policy POL
 proposal PROP
crypto ikev2 keyring KR
 peer ANY
  address 0.0.0.0 0.0.0.0
  pre-shared-key VERIDIAN-VPN-KEY
crypto ikev2 profile IKEV2-PROF
 match identity remote address 0.0.0.0
 authentication remote pre-share
 authentication local pre-share
 keyring local KR
 dpd 10 2 on-demand
crypto ipsec transform-set TS-AES-TRANSPORT esp-aes 256 esp-sha256-hmac
 mode transport
crypto ipsec profile VPN-PROF-NAT
 set transform-set TS-AES-TRANSPORT
 set ikev2-profile IKEV2-PROF
vrf definition MGMT
 rd 65010:99
 address-family ipv4
 exit-address-family
interface Loopback0
 ip ospf 1 area 23
interface Loopback10
 ip ospf network point-to-point
 ip ospf 1 area 23
interface Loopback99
 description Management
 vrf forwarding MGMT
 ip address 10.23.99.1 255.255.255.255
 ip ospf 99 area 0
interface Tunnel23
 description to HQ-WAN1 Tunnel23
 ip address 10.250.23.23 255.255.255.0
 ip mtu 1400
 ip tcp adjust-mss 1360
 ip ospf network point-to-point
 ip ospf hello-interval 5
 ip ospf dead-interval 20
 ip ospf cost 100
 ip ospf 1 area 23
 tunnel source Ethernet0/0
 tunnel mode gre ip
 tunnel destination 203.0.113.129
 tunnel protection ipsec profile VPN-PROF-NAT
interface Tunnel93
 description to HQ-WAN1 Tunnel93 (MGMT)
 vrf forwarding MGMT
 ip address 10.250.93.23 255.255.255.0
 ip mtu 1400
 ip tcp adjust-mss 1360
 ip ospf network point-to-point
 ip ospf hello-interval 5
 ip ospf dead-interval 20
 ip ospf cost 100
 ip ospf 99 area 0
 tunnel source Ethernet0/0
 tunnel mode gre ip
 tunnel destination 203.0.113.145
 tunnel protection ipsec profile VPN-PROF-NAT
router ospf 1
 router-id 10.255.23.1
 passive-interface Loopback10
router ospf 99 vrf MGMT
 router-id 10.255.23.1
 passive-interface Loopback99
line vty 0 4
 exec-timeout 10 0
 login authentication VTY
 authorization exec VTY
 transport input ssh
 access-class WAN-MGMT in vrf-also
line con 0
 login authentication CON
```

**CR3 (eBGP).** HQ-WAN1:
```
ip route 10.10.0.0 255.255.0.0 Null0
ip route 10.50.0.0 255.255.0.0 Null0
router bgp 65010
 bgp router-id 10.255.10.41
 neighbor 100.64.10.0 remote-as 64700
 address-family ipv4
  network 10.10.0.0 mask 255.255.0.0
  network 10.50.0.0 mask 255.255.0.0
  neighbor 100.64.10.0 activate
router ospf 1
 redistribute bgp 65010 subnets route-map PROV-ROUTES
 no redistribute static
no ip route 10.21.0.0 255.255.0.0 100.64.10.0
```
BR1-RTR1: `ip route 10.21.0.0 255.255.0.0 Null0`, `router bgp 65021` (router-id 10.255.21.1, neighbor 100.64.21.0 remote-as 64700, `network 10.21.0.0 mask 255.255.0.0`, activate), `no ip route 10.10.0.0 255.255.0.0 100.64.21.0`, `no ip route 10.50.0.0 255.255.0.0 100.64.21.0`. Gotcha: `no redistribute static subnets route-map PROV-ROUTES` removes only the keywords and leaves `redistribute static`, which leaks the new Null0 /16s into OSPF and the branches then black-hole the HQ /16: use `no redistribute static`.

**CR2 (AAA and time).** On BR1-RTR1, BR2-RTR1, BR3-RTR1 first, then HQ-WAN1:
```
radius server DC-AAA1
 address ipv4 10.50.50.52 auth-port 1812 acct-port 1813
 key RADKEY123
aaa group server radius RADGRP
 server name DC-AAA1
 ip vrf forwarding MGMT
 ip radius source-interface Loopback99        (HQ-WAN1: Ethernet0/2.99)
radius-server dead-criteria time 5 tries 2
radius-server deadtime 1
aaa authentication login VTY group RADGRP local
aaa authorization exec VTY group RADGRP local
aaa accounting exec VTY start-stop group RADGRP
ntp server vrf MGMT 10.50.50.1 key 1
```
BR1 and BR2 also `no ntp server 203.0.113.129 key 1`; HQ-WAN1 last: `no ntp master 3`. BR3 has no time source before CR2 (CR1 does not configure NTP on it); it takes 10.50.50.1 directly in CR2.

## Verification

Captured from the re-imported `ENCOR MS-3` lab (start state, then the solution scripts above applied) and from the build.

**Start state (V-symptoms at boot, re-imported lab):**
```
HQ-WAN1# show ip route 10.10.20.0
% Subnet not in table
HQ-WAN1# show ip protocols | include filtered
    Ethernet0/2 filtered by (prefix-list) HQ-IN (per-user), default is not set
BR2-RTR1# show ip route 10.10.20.0
% Subnet not in table
BR2-RTR1# show ip vrf interfaces
Lo99                   10.22.99.1      MGMT                             up
Tu92                   10.250.92.22    OT                               up
HQ-ACC1# show interfaces trunk       (Et0/0 allowed 10,99; Et0/1 10,20,99; STP forwarding: Et0/0 10,99 / Et0/1 20)
HQ-PC2: 10.10.20.1 and 192.0.2.200 3/3; 10.21.10.101 and 10.22.10.101 0/3 (100 % loss)
BR2-PC1: 10.10.10.101 3/3; 10.10.20.102 0/3
BR1-RTR1: track 30 Up, Target 100.64.10.0/Ethernet0/1; ip policy route-map VOICE-PBR on Ethernet0/2;
          service-policy output WAN-SHAPE on Ethernet0/1, none on Ethernet0/0; Policy routing matches: 0 packets
HQ-CORE1# telnet 10.21.99.1 22 /vrf MGMT /source-interface Ethernet0/1.99   -> Open, SSH-2.0-Cisco-1.25
HQ-CORE1# telnet 10.22.99.1 22 ...   -> % Destination unreachable; gateway or host down
```
While the backup job runs, BR1-PC1 pings show up to about 5 s round trips with 60 % loss and BR1's EF traceroute can leave via the provider next hops (the tunnel adjacencies flap on the dead timer); outside the job window: 72 ms, 0 % loss, EF traceroute 10.21.10.1, 10.250.21.1, 10.10.255.96.

**TK1:** F2 fixed alone: HQ-PC2 still 0/3 to the branches. F1 fixed alone: HQ-PC2 reaches BR1/BR2 and HQ-WAN1 `show ip route 10.10.20.0` is back to `ospf 1` within 5 s. End state: `Known via "ospf 1", distance 110, metric 20, type intra area` via 10.10.255.96, and `show ip ospf database summary 10.10.20.0` lists HQ-WAN1 (10.255.10.41) as advertising router in the branch areas.

**V7:** F2 fixed, ACC1 e0/1 + DIST2 e0/2 shut (cable pull), HQ-PC2 to BR2-PC1 at 1/s: 0 lost in 3 runs. ACC1 e0/0 + DIST1 e0/2: 0 lost. With F2 present the ACC1–DIST2 pull cuts VLAN 20 (62 lost until restored); the ACC1–DIST1 pull loses 0 (86/86 replies).

**TK2 / V3:** F5 alone: 7/3753 voice packets lost (0.19 %), still on the tunnel; F4 alone: 0/3753 on the provider line, `Policy routing matches: 3759`, but the drill black-holes (track 30 stays Up; 0 packets for the rest of the 50 s run); F3 fixed then F5 fixed: failover and ≤ 1.1 % loss (below). EF traceroute with all fixed: 100.64.21.0, 100.64.10.1 (PE1, HQ-WAN1 provider side).

**TK3:** F6 fixed: OSPF 99 FULL on HQ-WAN1 Tunnel92 (`10.255.22.1 FULL 10.250.92.22 Tunnel92`), `telnet 10.22.99.1 22 /vrf MGMT /source-interface Ethernet0/1.99` -> `% Connection refused by remote host`; F7 fixed: `Open`, `SSH-2.0-Cisco-1.25`, `show access-lists WAN-MGMT` `10 permit 10.10.99.0, wildcard bits 0.0.0.255 (8 matches)`.

**CR1 (BR3), captured:**
```
PROV-INET1# show ip nat translations
udp 203.0.113.136:4785 100.64.23.1:500  203.0.113.129:500  203.0.113.129:500
udp 203.0.113.136:4786 100.64.23.1:4500 203.0.113.129:4500 203.0.113.129:4500
udp 203.0.113.136:4787 100.64.23.1:500  203.0.113.145:500  203.0.113.145:500
udp 203.0.113.136:4788 100.64.23.1:4500 203.0.113.145:4500 203.0.113.145:4500
HQ-WAN1# show crypto ikev2 sa     (7 READY: 203.0.113.129/4500 <-> 203.0.113.136/4786 and 203.0.113.145/4500 <-> 203.0.113.136/4788 among them)
HQ-WAN1# show crypto ikev2 sa detailed | include NAT-T      -> NAT-T is detected  outside (BR3 SAs)
BR3-RTR1# show crypto ikev2 sa detailed | include NAT-T     -> NAT-T is detected inside
BR3-RTR1# show crypto ipsec sa | include UDP-Encaps         -> Transport UDP-Encaps (all four SAs)
BR3-RTR1# ping 10.10.10.101 source Loopback10 size 1400 df-bit repeat 2   -> !! 100 percent
BR3-RTR1# ping 10.10.10.101 source Loopback10 size 1401 df-bit repeat 2   -> .. 0 percent (tunnel MTU 1400)
```
Tunnel mode (`VPN-PROF`) first: line protocol down; `debug crypto ikev2 error` on HQ-WAN1 `Failed to find a matching policy` (build). Both tunnels FULL: `10.255.23.1 FULL 10.250.23.23 Tunnel23` and `... 10.250.93.23 Tunnel93`. Pings from BR3 Loopback10 to 10.10.20.102, 10.21.10.101 and 10.22.10.101: 100 %; the Internet host 192.0.2.200 answers from BR3 Ethernet0/0 only (`ping 192.0.2.200 source Loopback10` is 0/2: the users network 10.23.10.0/24 is not translated on INET1, which only handles BR3's carrier address 100.64.23.1; BR3 users' Internet access is not a requirement); HQ-PC1, HQ-PC2, BR1-PC1, BR2-PC1 to 10.23.10.1: 3/3. Hardened: BR3 Loopback99 (VRF MGMT) reaches DC-AAA1 10.50.50.52 and CORE1 10.10.99.2 (build); `telnet 10.23.99.1 22 /vrf MGMT /source-interface Ethernet0/1.99` from CORE1 returns the SSH banner.

**CR2 (AAA, time):** `test aaa group RADGRP netadmin netpass new-code` on HQ-WAN1 and BR3 -> `User successfully authenticated`, `priv-lvl 15 (0xF)`; `netops`/`opspass` -> priv-lvl 1 (BR2, build); DC-AAA1 log `Login OK: [netadmin] (from client lab port 0)`; local fallback by the method list `group RADGRP local` with `radius-server dead-criteria`/`deadtime 1`. `show aaa servers` on BR1: `RADIUS: id 1, priority 1, host 10.50.50.52, auth-port 1812, acct-port 1813, hostname DC-AAA1`. SSH from CORE1 through MGMT (source 10.10.99.2) returns the banner for 10.21.99.1, 10.22.99.1, 10.23.99.1, WAN1 10.10.254.11 and DC-RTR1 10.50.50.1 (build); refused from the global table (source Loopback0) and on port 23. V8 (build): 36 minutes after CR2, `sys.peer` is 10.50.50.1 (stratum 4) on HQ-WAN1, BR1, BR2, BR3 and CORE1. Order: branches first (derived reason: HQ-WAN1 without `ntp master` and not yet synchronised would leave branches on a stratum-16 source).

**CR3 (eBGP), captured:**
```
PROV-PE1# show ip bgp summary
100.64.10.1     4        65010      17      18        4    0    0 00:12:25        2
100.64.21.1     4        65021      17      19        4    0    0 00:12:28        1
HQ-WAN1# show ip bgp
 *>   10.10.0.0/16     0.0.0.0                  0         32768 i
 *>   10.21.0.0/16     100.64.10.0                            0 64700 65021 i
 *>   10.50.0.0/16     0.0.0.0                  0         32768 i
BR1-RTR1# show ip bgp
 *>   10.10.0.0/16     100.64.21.0                            0 64700 65010 i
 *>   10.21.0.0/16     0.0.0.0                  0         32768 i
 *>   10.50.0.0/16     100.64.21.0                            0 64700 65010 i
HQ-WAN1# show ip route 10.21.0.0 | include Known       Known via "bgp 65010", distance 20, metric 0
```
`show ip route static` at the end: HQ-WAN1 only the default, the two Null0 /16 anchors and the probe /31 (100.64.21.0/31 via 100.64.10.0); BR1 only the default, the Null0 /16 and the probe /31; BR2 and BR3 only their defaults. HQ-WAN1 redistributes the BGP 10.21.0.0/16 into OSPF 1 as E2 (metric 1). With Tunnel21 down, the BGP /16s carry traffic (build).

**End state (V1):** end checks after all items: HQ-WAN1 OSPF FULL x9 (CORE1, Tunnel21/22/23/41/91/92/93 and the MGMT sub-interface), OSPF 99 FULL x4; every PC and BR3 Loopback10 ping in the table 3/3 (internal destinations) (one isolated first-packet loss HQ-PC1 to BR2-PC1, 2/3); Internet host 192.0.2.200 reachable from HQ-PC1, BR1-PC1 and from BR3 Ethernet0/0 (not from BR3 Loopback10). BR2-PC1 was not measured against 192.0.2.200 and is not required to reach it; the hosts that do are HQ-PC1, HQ-PC2 and BR1-PC1 (HQ-PC2 3/3 in the start-state capture above, BR1-PC1 and HQ-PC1 in the end checks; no host lost it through the solution). The data-centre services (10.50.50.0/24) are in VRF MGMT only: user hosts get 100 % loss to 10.50.50.x by design; reach them from the management network (V4). V5: both sessions Established at PE1 above; V6: HQ-PC1 and HQ-PC2 reach 192.0.2.200 in the end checks; no change touches HQ-EDGE1, so its EDGE-IN denies are unchanged (derived, not re-tested).

V4 test method (not separately captured; use it as the reference): the lab has no SNMP client (DC-AAA1 has no CLI, IOS has no `snmpget`, the hosts have no `snmpget`/`snmpwalk`), so SNMPv3 is checked at config level on a WAN router: `show snmp user` (nmsuser), `show snmp group` (NMSGROUP, `access WAN-MGMT`) and `show ip access-lists WAN-MGMT` (management hosts permitted, the rest denied); an unauthenticated SNMPv3 discovery probe is answered from any source, so it is not a valid test; for the AAA fallback take DC-AAA1 away silently (`tools/cml-rest.sh link stop <lab> "DC-RTR1-Ethernet0/1<->DC-AAA1-eth0"`; `link start` restores) and log in as the local user `admin` from HQ-CORE1 (`ssh -l admin -vrf MGMT 10.23.99.1`): measured 10.5, 13.8 and 10.5 s over 3 runs (RADIUS dead criteria and `deadtime 1`), 0.3-0.4 s with the server up, and `netadmin` is refused while the server is down. V5 with the BR1 failure: a cable pull of BR1 Ethernet0/0 (or silent failure of its Internet link) removes Tunnel21, 41 and 91 together; then the BGP /16s learned over the provider service carry BR1-HQ traffic (build; no per-state traceroute captured), and with the tunnels up `show ip route 10.10.10.0` / `10.21.0.0` use the tunnels (OSPF).

Verification note: `telnet <router> 22 /vrf MGMT` to an accepting SSH server holds the console for about 120 s; a scripted session needs a timeout above 120 s or it trips.

## Failure / Recovery Behaviour

Methods: V7 = cable pull (`shutdown` on both ends); V3 drill (run with a hand-started 3 Mb/s UDP stream from BR1-PC1 for the whole drill) and the second BR3 test = silent failure (`tools/cml-rest.sh link stop <lab> "HQ-WAN1-Ethernet0/1<->PROV-PE1-Ethernet0/0"`, restore with `link start`); BR3 cable pull = `shutdown` on BR3 e0/0 and INET1 e0/3. Raw values are measured runs; documented ranges cover the runs and the protocol timers (OSPF dead 20 s, hello 5 s; DPD `10 2 on-demand`; SLA frequency 5 s + timeout 1 s + delay down 5 s / up 30 s).

| Scenario (trigger -> end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| V7: cable pull ACC1 e0/1 + DIST2 e0/2 (F2 fixed), pings at 1/s HQ-PC2 -> BR2-PC1 -> pings lost | 0, 0, 0 | at most 3 lost | RSTP alternate-port flip is below one ping interval; limit adds three pings of margin |
| V7: cable pull ACC1 e0/0 + DIST1 e0/2 (F2 present or fixed) -> pings lost | 0 (86/86 replies) | at most 3 lost | as above |
| V3 drill: silent failure of HQ-WAN1 e0/1 <-> PE1 e0/0 -> `Up -> Down` of track 30 at BR1 (stamps are the host clock before/after the REST call) | 10.0-12.4 s, 13.1-16.4 s, 12.5-15.3 s | track Down 8-20 s; calls on the Internet path within 25 s | SLA 5 s + timeout 1 s + delay down 5 s plus jitter of the first missed probe; limit adds 5 s over the worst 16.4 s |
| V3 drill: voice gap at the server (BR1 -> HQ-PC1) after the stop | 10, 11, 11 whole zero-seconds plus partial seconds (about 11-13 s) | at most 25 s | follows the track change; same limit |
| V3 drill: loss after failover, upload running, per 185 packets | <= 2 lost (<= 1.1 %) | at most 5 % per second | conditioning 0.2 % plus the shaped 2 Mb/s circuit under 3 Mb/s of offered bulk |
| V3 drill: `link start` -> track 30 `Down -> Up` (calls back on the provider line) | 34.1, 34.0, 36.0 s | 30-90 s | delay up 30 s plus the probe period; limit adds margin |
| BR3 cable pull (BR3 e0/0 + INET1 e0/3) -> HQ-WAN1 neighbour 10.250.23.23 gone (scripted session elapsed time) | 19, 21, 21 s | 15-30 s | dead interval 20 s; HQ-WAN1 gets no interface-down |
| BR3 cable pull restored (`no shutdown` both ends) -> Tunnel23 neighbour FULL on HQ-WAN1 | 22, 22, 19 s | 15-60 s | IKE re-negotiation behind the PAT plus hello/dead exchange |
| BR3 silent failure (link stop BR3 e0/0 <-> INET1 e0/3) -> HQ-WAN1 OSPF dead (Tunnel93 / Tunnel23) | 16.3-22.1 s over 3 runs (e.g. run 1 09:21:27.33 / 09:21:30.83 against stop 09:21:08.7-11.0) | 15-30 s | dead interval 20 s measured from the last hello |
| same -> tunnel line protocol down (DPD) | 19.1-26.1 s | 15-40 s | DPD `10 2 on-demand` fires after the dead timer |
| same, `link start` -> Tunnel93 FULL / Tunnel23 FULL | Tunnel93 3.1-16.8 s, Tunnel23 12.3-26.1 s | 3-45 s (Tunnel23 about 9-10 s after Tunnel93) | IKE negotiations start independently; Tunnel23's starts later |

V9 in LAB.md uses 30 s to drop and 60 s to return (worst measured 26.1 s and 26.1 s). Other results: the BR1 job (UDP 3 Mb/s, 120 s every 10 minutes) with F5 present drops the BR1 tunnel adjacencies on the dead timer and queues pings to about 5 s (even 2.2 Mb/s flaps Tunnel41/91); with F5 fixed, ping RTT is 72 ms with 0 % loss and no new adjacency drops. This is the consequence the ticket points to; students must not stop the job to "fix" it.

## Answers to Analysis Questions

**Q1.** Suggested order: constraints and the documentation pack first; TK3 (F6 then F7) and TK1 (F1; F2 found on the way) because they are quick and independent; TK2 (F4, F5, then F3 through the drill); CR1 (BR3); CR3; CR2 last for the branches-first reason; V8 last. Dependencies: CR2 on BR2 cannot be verified until TK3 is fixed (BR2 is unreachable from MGMT); V7 is only meaningful after F2 is understood; TK2's second half needs the V3 drill, which needs CR3 not to have renumbered anything; V8 needs time.

**Q2.** TK1: after F2 alone, HQ-PC2 still loses the branches (nothing changed); after F1, `show ip route 10.10.20.0` on HQ-WAN1 is OSPF and the branches reply. TK2: after F5 alone, the loss is 0.19 % but `traceroute -t 184` still goes via 10.250.21.1; after F4 the PBR counters rise and the route is 100.64.21.0 -> 100.64.10.1; after the drill with F3 present, the stream stops (track Up) until F3 is fixed. TK3: after F6, OSPF 99 is FULL but SSH is refused immediately (`WAN-MGMT` has no matches); after F7, the banner appears and the ACL counts.

**Q3.** INET1 translates BR3's 100.64.23.1 to 203.0.113.136 and changes the source ports: IKE 500 becomes 4785/4787 and the NAT-T floated 4500 becomes 4786/4788; the ESP is UDP-encapsulated (GRE appears in the NAT table only as a translated ID). HQ sees 203.0.113.136 as the peer and flags `NAT-T is detected outside`; BR3 flags `inside`. In tunnel mode the child SA fails across the PAT (`Failed to find a matching policy`): both ends use the transport-mode IPsec profile (`VPN-PROF-NAT`) with the tunnel endpoints at the translated address (destination 203.0.113.136 on HQ-WAN1), and HQ-WAN1's circuit policy admits UDP 500/4500 from 203.0.113.136 only (no ESP). MTU: `Tunnel transport MTU 1418`, tunnel MTU 1400 (DF 1400 passes, 1401 fails).

**Q4.** The call (EF, 300 kb/s) must be tested against the saturating upload (UDP 3 Mb/s against a 2 Mb/s circuit): without it the loss is invisible (0.2 % conditioning). Before the fixes: calls on the tunnel, 30-70 % lost under the upload; after F4: on the provider line; after F5: queued correctly (priority class). The shaper/queue on the Internet circuit, the SLA target and the track state are visible only when the provider path fails (the drill): the call must move to the Internet path in at most 25 s and then lose at most 5 %.

**Q5.** The branches take time from HQ-WAN1 (`ntp master 3`); if HQ-WAN1 stops being the master or repoints before it is synchronised to DC-RTR1, the branches are left with a stratum-16 source. So the branches are repointed to 10.50.50.1 through MGMT first, HQ-WAN1 last (the build's order). Any order that keeps every branch on a synchronised source (`sys.peer`) until its new source is selected is accepted, for example HQ-WAN1 syncing to DC-RTR1 first while keeping `ntp master`, the branches adding DC-RTR1 as a second source, and `no ntp master` last; the check is last because a router needs minutes to select a new source (`show ntp associations` `sys.peer`, 36 minutes in the build, up to 45 minutes allowed in LAB.md). AAA is checked with `test aaa group RADGRP …` and the DC-AAA1 log, plus the local fallback.

**Q6.** HQ-WAN1 announces 10.10.0.0/16 and 10.50.0.0/16 (Null0 anchors and `network` statements, PE1 accepts exactly these) and redistributes the BGP-learned 10.21.0.0/16 into OSPF 1 with the route map `PROV-ROUTES` (E2); BR1 announces 10.21.0.0/16. The statics that the sessions replace are removed; the probe /31s and defaults stay. Proof: with the tunnels up users use OSPF /24s (longest match); with Tunnel21 down the BGP /16s carry traffic (AD 20 against the removed static AD 1); the EF traceroute is still 100.64.21.0 -> 100.64.10.1 and the track still follows the SLA to 100.64.10.1.

**Q7.** Time-dependent: V3 (SLA and delay timers; the job window changes BR1's results: wait for or avoid the 120 s job windows, or repeat the upload by hand (`iperf -u -b 3M`, user `cisco`, a port other than 5002) to cover the whole drill, which does not fit in one window; start 2 minutes after boot and every 10 minutes), V9 (dead timers, DPD), V7 (spanning tree), V8 (NTP selection, up to 45 minutes). They are checked after the tunnels and BGP have settled, V8 last.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-18 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a), radius |
