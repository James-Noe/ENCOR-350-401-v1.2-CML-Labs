# MS-2 — Solution

## Summary

MS-2 closes modules 01–05 on HQ H3 (hardened campus, MGMT VRF, central AAA) joined to a single-ISP edge (E0 lite). The student works a change queue (CR1 guest VLAN, CR2 IPv6 Internet, CR3 edge management) and a ticket queue (TK1–TK3), each ticket with two faults, and proves the result with failure drills. Six faults, three tickets: TK1 = F1 + F2 in series, TK2 = F3 + F4 in parallel, TK3 = F5 + F6 in series. Work TK3 first: copying CORE1's AAA lines to the edge for CR3 copies F5/F6. CR1 cannot pass until F1's NAT list is reconciled with the documented policy.

Blueprint mapping: 3.1.a (trunks/native VLAN, TK2, CR1), 3.3.b (NAT, TK1 F1, CR1), 3.3.c (first-hop redundancy, CR1, V3), 3.2.b (OSPF including the RIB filter, TK1 F2), 3.2.c (BGP, CR2), 5.1.a/5.1.b (device access and AAA, TK3, CR3), 5.2.a (ACLs, CR1, CR3), 4.1 (syslog/SNMP, CR3), 3.3.a (NTP, CR3), 2.2.a (VRF MGMT on the edge, CR3), IPv6 (CR2).

Platform notes: node stop is a silent failure (no HSRP/VRRP resign); cable pull = `shutdown` on both ends; ioll2-xe does not block a PVID-inconsistent port (the F4 effect is that VLAN 99 is lost on that link and CDP logs the mismatch); NTP is in the start state on every device except HQ-EDGE1 (CR3 adds it there); switches (ioll2-xe) can take about 25 min to reach sys.peer, so check them last in V2. After wiping directly linked IOL nodes separately, check for one-way links (a known CML behaviour); a whole-lab wipe was clean.

## Intentional Faults

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-EDGE1 | ACL `NAT-INSIDE` lists only 10.10.10.0/24 and 10.10.50.0/24 (VLAN 20 missing; original was 10.10.0.0/16) | VLAN 20 traffic leaves untranslated (private source), ISP-A has no route back. Also leaves VLAN 30 untranslated after CR1 |
| F2 | HQ-CORE2 | `router ospf 1` `distribute-list prefix NO-DEFAULT in` (prefix-list denies 0.0.0.0/0, permits the rest) | CORE2 has no default route (`% Network not in table`) although the LSA is in its database and flooded on; VLAN 20 (VRRP master CORE2) gets host-unreachable from 10.10.20.3. VLAN 10 (DIST default via CORE1) and VLAN 50 (master CORE1) unaffected |
| F3 | HQ-DIST1 e0/3 | `switchport trunk allowed vlan 10,20` (99 missing) | ACC2's VLAN 99 cannot use its DIST1 uplink |
| F4 | HQ-ACC2 e0/1 | `switchport trunk native vlan 99` (DIST2 side keeps 999) | VLAN 99 leaves ACC2 untagged and arrives in VLAN 999 at DIST2: VLAN 99 lost on that link; CDP native-VLAN mismatch (99 vs 999) |
| F5 | HQ-CORE1 | `radius server DC-AAA1` key re-typed `RADKEY12` (should be `RADKEY123`) | AAA1 rejects the (garbled) password and the accounting requests; CORE1 discards the reply, times out, marks the server dead, falls back to local: only `admin` logs in |
| F6 | HQ-CORE1 | `aaa authorization exec VTY local` (`group RADGRP` dropped) | after F5 is fixed RADIUS authentication succeeds but exec authorization has no local user: session refused |

Fault logic (all proved in testing): TK1 series, TK2 parallel, TK3 series. Cross-effects: F1 also breaks CR1's guests; ACC2's users are unaffected by TK2 (VLANs 10/20 still forward on both uplinks), the red herring for TK1 (PC2 reaches every internal destination).

Red herrings: EDGE1 pings the Internet host; ISP-A's view shows pool A announced; `show ip ospf database external` on CORE2 lists the default; the DMZ port on EDGE1 is down (documented); after F3 is fixed the ACC2-DIST2 link still loses VLAN 99 (F4, not a design property); boot-time RADIUS dead messages before DC-AAA1 is ready.

Wrong-fix traps: static default on CORE2 (violates "defaults only from the edge", black-holes if the edge default is withdrawn); `NAT-INSIDE permit 10.10.0.0 0.0.255.255` (translates infrastructure, violates the documented policy); removing the guest ACL or NAT tricks; a local `netadmin` on CORE1 (no accounting, violates policy); native VLAN 99 on DIST2 too (works, violates native 999 and leaves VLAN 99 untagged on one trunk).

## Diagnosis / Methodology

Order that works: TK3, TK2, TK1 (any order is possible; TK3 first protects CR3), then CR1, CR2, CR3.

**TK1 (OPS cannot reach the Internet).** Plausible subsystems and how each is ruled in or out:

| Subsystem | Evidence | Verdict |
|---|---|---|
| OPS host / access path (VLAN 20, ACC2) | PC2 `ping 10.10.50.103` (internal) 3/3; traceroute `1 10.10.20.3  2 10.10.20.3 !H` | ruled out: the access path works; the first hop answers |
| VLAN 20 gateway (VRRP) | CORE2 MASTER for VLAN 20 (pri 110), CORE1 BACKUP | gateway fine; the master is the router that drops the packet |
| Core routing / default | CORE1 `show ip route 0.0.0.0`: `* 10.10.255.65 ... Ethernet0/3`; CORE2: `% Network not in table`, yet `show ip ospf database external` lists 0.0.0.0; DIST1 default via 10.10.255.2 (Vlan901), DIST2 via 10.10.255.4 (Vlan902) | confirmed (F2): a RIB filter, not an LSA filter; only the VLAN whose master is CORE2 is hit |
| Edge NAT | `show access-lists NAT-INSIDE` lists 10.10.10.0/24 and 10.10.50.0/24 only; after F2 is fixed, `show ip nat translations \| include 10.10.20` is empty and traceroute dies beyond EDGE1 | confirmed (F1), exposed only after F2 |
| Edge BGP / provider | `show ip bgp summary` Up, 2 prefixes; EDGE1 and PC1/PC3 reach 192.0.2.200 | ruled out |

Fixing F2 only: VLAN 20 packets reach EDGE1 and leave untranslated (traceroute `1 10.10.20.3  2 10.10.255.0  3 10.10.255.65  4 * * *`). Fixing F1 only: no change (CORE2 still drops).

**TK2 (ACC2 red).** `ping 10.10.99.22` from DC-NMS1 fails while `10.10.99.21` (ACC1) works. ACC2 `show interfaces trunk`: Et0/1 native VLAN 99; `%CDP-4-NATIVE_VLAN_MISMATCH` on both ends: `Ethernet0/1 (99), with HQ-DIST2 Ethernet0/3 (999)`. DIST1 `show interfaces e0/3 trunk` shows 99 not allowed. Management SVI, gateway and the MGMT VRF on the cores are ruled out because ACC1 on the same gateway works. Either fix restores the ping (F3 only: OK after 7 s; F4 only: OK after 8 s); the remaining fault is exposed by V3's cable pull of the healthy uplink (the other path is then needed). `show spanning-tree inconsistentports` = 0 on ioll2-xe: no PVID block, the effect is only VLAN 99 lost on that link.

**TK3 (personal accounts fail on CORE1).** `ssh netadmin@CORE2` from DC-NMS1 works (priv 15), `ssh netadmin@CORE1` is closed, `admin@CORE1` works: only CORE1. AAA1 console: `Received Accounting-Request packet from client 10.10.99.2 with invalid Request Authenticator! (Shared secret is incorrect.)` and `Login incorrect (pap: Cleartext password does not match ...)`; CORE1 `show aaa servers`: `State: current DEAD`. Path to the server and the account database are ruled out (CORE2 works with the same server). Fix F6 only: still `Connection closed by 10.10.254.2` (server dead, `%RADIUS-3-NOSERVERS`). Fix F5, F6 left: after the 1 min deadtime (`%RADIUS-6-SERVERALIVE`) AAA1 logs `Login OK: [netadmin]` and CORE1 `%SEC_LOGIN-5-LOGIN_SUCCESS [user: netadmin]` but the client gets `% Authorization failed.` and is closed. The symptom changes only after the deadtime; a local `netadmin` is a wrong fix.

## Solution Configuration

All scripts below were run as written.

**Tickets**
```
! TK1 F2, F1
HQ-CORE2:  router ospf 1
            no distribute-list prefix NO-DEFAULT in
           no ip prefix-list NO-DEFAULT
HQ-EDGE1:  ip access-list standard NAT-INSIDE
            15 permit 10.10.20.0 0.0.0.255
           exec: clear ip nat translation *
! TK2 F3, F4
HQ-DIST1:  interface Ethernet0/3
            switchport trunk allowed vlan 10,20,99
HQ-ACC2:   interface Ethernet0/1
            switchport trunk native vlan 999
! TK3 F5, F6
HQ-CORE1:  radius server DC-AAA1
            key RADKEY123
           aaa authorization exec VTY group RADGRP local
```

**CR1 (guest VLAN 30; HSRP group 30, DIST2 active)**
Acceptance for R3(b): HSRP or VRRP passes (Active/Master on DIST2, DIST2 preempts). GLBP fails R3(b) unless DIST2 is the only forwarder, because the AVG would let DIST1 forward as an AVF as well.
```
HQ-DIST2:  vlan 30 / name GUEST
           spanning-tree vlan 30 priority 24576
           ip access-list extended GUEST-IN
            permit udp any host 224.0.0.2 eq 1985
            permit icmp any host 10.10.30.1 echo
            permit udp any eq bootpc any eq bootps
            deny ip any 10.0.0.0 0.255.255.255 log
            permit ip any any
           interface Vlan30
            ip address 10.10.30.3 255.255.255.0
            ip access-group GUEST-IN in
            ip ospf 1 area 10
            standby 30 ip 10.10.30.1
            standby 30 priority 110
            standby 30 preempt delay minimum 30
            no shutdown
           interface Port-channel1 / interface Ethernet0/2
            switchport trunk allowed vlan add 30
HQ-DIST1:  vlan 30 / name GUEST
           spanning-tree vlan 30 priority 28672
           ip access-list extended GUEST-IN (same five lines as DIST2)
           interface Vlan30
            ip address 10.10.30.2 255.255.255.0
            ip access-group GUEST-IN in
            ip ospf 1 area 10
            standby 30 ip 10.10.30.1
            standby 30 priority 100
            standby 30 preempt
            no shutdown
           interface Port-channel1 / interface Ethernet0/2: switchport trunk allowed vlan add 30
HQ-ACC1:   vlan 30 / name GUEST
           interface Ethernet0/0 and Ethernet0/1: switchport trunk allowed vlan add 30
           interface Ethernet1/1
            switchport access vlan 30
            switchport mode access
            spanning-tree portfast
            spanning-tree bpduguard enable
HQ-EDGE1:  ip access-list standard NAT-INSIDE
            25 permit 10.10.30.0 0.0.0.255
           exec: clear ip nat translation *
```
The UDP 1985 and DHCP lines are not needed with this ACL: their destinations (224.0.0.2, or 224.0.0.102 for HSRPv2; the broadcast address for DHCP) are not in 10.0.0.0/8 and the last line permits them; they become required if the ACL ends in `deny ip any any`. Guests can still reach EDGE1's Internet-facing addresses through `permit ip any any`: these are public addresses protected by the edge's own management ACL (CR3), so this is accepted for R3(d). (Derived from the ACL logic; not tested without these lines.) Use `allowed vlan add`, never a replacing list.

**CR2 (IPv6 over ISP-A)**
```
HQ-CORE1:  interface Ethernet0/3
            ipv6 address 2001:DB8:10:FFFF::64/127
            ospfv3 1 ipv6 area 0 / ospfv3 network point-to-point / ospfv3 cost 10
            ospfv3 hello-interval 1 / ospfv3 dead-interval 4
           router ospfv3 1 / address-family ipv6 unicast / no passive-interface Ethernet0/3
HQ-EDGE1:  ipv6 unicast-routing
           interface Ethernet0/0: ipv6 address 2001:DB8:F001:FFFF::65/127
           interface Ethernet0/1: ipv6 address 2001:DB8:10:FFFF::65/127, ospfv3 1 ipv6 area 0,
             ospfv3 network point-to-point, cost 10, hello 1, dead 4
           interface Loopback0: ipv6 address 2001:DB8:FFFF:10::31/128, ospfv3 1 ipv6 area 0
           router ospfv3 1: router-id 10.255.10.31; address-family ipv6 unicast:
             passive-interface default, no passive-interface Ethernet0/1, default-information originate metric 10
           ipv6 route 2001:DB8:10::/48 Null0
           ipv6 prefix-list VERIDIAN-OUT-6 seq 5 permit 2001:DB8:10::/48
           ipv6 prefix-list ISPA-IN-6 seq 5 permit ::/0 ; seq 10 permit 2001:DB8:F001::/48
           route-map ISPA-OUT-6 permit 10 / match ipv6 address prefix-list VERIDIAN-OUT-6
           route-map ISPA-IN-6 permit 10 / match ipv6 address prefix-list ISPA-IN-6
           router bgp 65010
            neighbor 2001:DB8:F001:FFFF::64 remote-as 64601
            neighbor 2001:DB8:F001:FFFF::64 password ISPA-64601
            address-family ipv6: network 2001:DB8:10::/48; neighbor ... activate;
             neighbor ... route-map ISPA-IN-6 in; neighbor ... route-map ISPA-OUT-6 out
```

**CR3 (EDGE1 under the management standard)**
```
HQ-CORE1:  interface Ethernet0/3.99
            encapsulation dot1q 99 / vrf forwarding MGMT / ip address 10.10.254.4 255.255.255.254
            ip ospf 99 area 0 / ip ospf network point-to-point / ip ospf cost 10
            ip ospf hello-interval 1 / ip ospf dead-interval 4
           router ospf 99 vrf MGMT: no passive-interface Ethernet0/3.99
HQ-EDGE1:  vrf definition MGMT / address-family ipv4
           interface Ethernet0/1.99: encapsulation dot1q 99, vrf forwarding MGMT,
             ip address 10.10.254.5 255.255.255.254, ip ospf 99 area 0, p2p, cost 10, hello 1, dead 4
           router ospf 99 vrf MGMT: router-id 10.10.254.5; passive-interface default;
             no passive-interface Ethernet0/1.99
           ip access-list standard MGMT-HOSTS: 10 permit 10.10.99.0 0.0.0.255; 20 permit 10.50.50.0 0.0.0.255; 40 deny any log
           ipv6 access-list NO-VTY6: deny ipv6 any any log
           aaa new-model
           aaa authentication login CON none ; aaa authentication enable default enable none
           radius server DC-AAA1: address ipv4 10.50.50.52 auth-port 1812 acct-port 1813 ; key RADKEY123
           aaa group server radius RADGRP: server name DC-AAA1 ; ip vrf forwarding MGMT ; ip radius source-interface Ethernet0/1.99
           radius-server dead-criteria time 5 tries 2 ; radius-server deadtime 1
           aaa authentication login VTY group RADGRP local
           aaa authorization exec VTY group RADGRP local
           aaa accounting exec VTY start-stop group RADGRP
           logging host 10.50.50.51 vrf MGMT ; logging trap informational ; logging source-interface Ethernet0/1.99 vrf MGMT
           snmp-server group NMSGROUP v3 priv access MGMT-HOSTS
           snmp-server user nmsuser NMSGROUP v3 auth sha AUTHPASS123 priv aes 128 PRIVPASS123
           ntp authentication-key 1 hmac-sha2-256 NTPKEY123 ; ntp authenticate ; ntp trusted-key 1
           ntp server vrf MGMT 10.50.50.1 key 1
           line con 0: login authentication CON
           line vty 0 4: login authentication VTY ; authorization exec VTY ; accounting exec VTY ;
             exec-timeout 10 0 ; transport input ssh ; access-class MGMT-HOSTS in vrf-also ; ipv6 access-class NO-VTY6 in
```
EDGE1 e0/1 keeps its global address and NAT-inside role; the dot1q 99 subinterface sits beside it (no fallback needed). Save with `copy running-config startup-config` on every changed device.

## Verification

**V1 matrix.** Users (VLANs 10/20/50): Internet IPv4 yes; IPv6 yes for the dual-stack VLANs 10/20/50; other user VLANs and the servers floor yes; 10.10.99.0/24, 10.10.254.0/24 and 10.50.50.0/24 no. Guests (VLAN 30): their gateway .1 and Internet IPv4 only.

**V3 expected values (tie each to its timer; ranges are in the Failure / Recovery table).** Access uplink pull: 0-1 lost (Rapid-PVST alternate port already in place). AAA node stop: 10-12 s for a login (RADIUS timeout, then local fallback, until the deadtime lapses). Core stop: 3-5 s for a VRRP-mastered VLAN (3 x advert + skew); about 40-45 s where the documented single attachment applies (Internet on CORE1, DC block and management on CORE2), until the node returns and OSPF converges.

Captured in CML. Each CR was run with background pings (1/s, 110 pings) from PC1, PC2 and PC3 to 192.0.2.200: **110/110 received on all three after every CR (0 lost; limit 5).**

- **Tickets:** PC1/PC2/PC3 ping 192.0.2.200 3/3; PC2 reaches 10.10.50.103; NMS pings ACC1 and ACC2; `netadmin` privilege 15 and `netops` privilege 1 on CORE1; CORE1 `show aaa servers` `State: current UP`. Start state, for contrast (on a fresh import): PC2 `100% packet loss`, traceroute `1  10.10.20.3 ... 2  10.10.20.3 !H`; NMS ping 10.10.99.22 `100% packet loss`; `netadmin@10.10.254.2`: `Connection closed by 10.10.254.2 port 22`.
- **CR1:** DIST2 `standby 30` Active, priority 110, preempt delay 30; DIST1 Standby 100; STP VLAN 30 root DIST2 (`24606` = 24576+30). PC4: ping 10.10.30.1 3/3; 192.0.2.200 3/3 (EDGE1 `icmp 192.0.2.1:1027 10.10.30.104:2`); 10.10.30.2, 10.10.10.101, 10.10.50.103, 10.255.10.1, 10.10.255.64: 100% loss.
- **CR2:** EDGE1 `show bgp ipv6 unicast summary` Up with 2 prefixes (`::/0`, `2001:DB8:F001::/48`); IPv4 session uptime continued (00:15:23, no reset); OSPFv3 FULL to CORE1; DIST1/CORE1 `show ipv6 route ::/0` via ospf 1; PC1/PC2/PC3 `ping6 2001:db8:f001:200::200` OK; PC4 `Network unreachable` (no IPv6 on the guest VLAN, correct). ISP1 learns 2001:DB8:10::/48 only. Converged under 20 s after the last command.
- **CR3:** EDGE1 OSPF 99 neighbour with 10.10.254.4 (CORE1 side) and route to 10.50.50.52 via ospf 99; AAA `State: UP`; `show ntp associations` `*~10.50.50.1`; BGP IPv4 uptime kept; from NMS: ping 10.10.254.5 OK, ssh `netadmin` and `netops` OK (EDGE1 `%SEC_LOGIN-5-LOGIN_SUCCESS ... Source 10.50.50.60`), `snmpwalk -v3 -l authPriv -u nmsuser -a SHA -A AUTHPASS123 -x AES -X PRIVPASS123 10.10.254.5 1.3.6.1.2.1.1.5.0` -> `"HQ-EDGE1.veridian.example"`; PC1 and PC4 ping 10.10.254.5: 100% loss (no path into MGMT).
- **Causality:** see Diagnosis.

## Failure / Recovery Behaviour

Method: busybox `ping` at 1/s from a host (lost `seq` numbers = seconds lost, 1 s resolution); trigger by a scripted CLI config block (cable pull = `shutdown` both ends) or `cml-rest.sh node stop` (silent failure for neighbours); end condition = replies resume. State: solved, saved with `write memory` on the stopped core.

| Scenario (trigger, end condition) | Runs (raw values) | Documented range | Basis |
|---|---|---|---|
| Cable pull ACC2-DIST1 (ACC2 e0/0 + DIST1 e0/3 shutdown), then ACC2-DIST2 (ACC2 e0/1 + DIST2 e0/3), 70 pings from NMS to ACC2 and from PC2 to 192.0.2.200; end = replies continue, then `no shutdown` both ends | 3 runs per uplink, 6 total: 0 lost in all, both streams | 0–1 lost per stream | Rapid-PVST alternate port takes over in under 1 s; no timers involved |
| Node stop of DC-AAA1, login as local `admin` through NMS ssh timed with `date +%s`; end = prompt | CORE2 11, 11, 11 s; EDGE1 10, 11, 10 s (server marked DEAD, `State: current DEAD`) | 10–12 s | RADIUS timeout then local fallback, until the 1 min deadtime lapses; restart: netadmin accepted again within 200 s |
| Node stop of HQ-CORE2 (stop at t+10 s, start 31 s later), PC2 -> 192.0.2.200 (VLAN 20, master CORE2); end = replies resume | lost: 3, 4, 3 s at the stop; 1, 0, 0 s when CORE2 returned and preempted | 3–5 s | VRRP master-down timer (3 x advert + skew) |
| same, PC1 -> 10.10.50.103 | 4+1, 4+2, 3+2 lost | 3–6 s | VRRP/GLBP failover; the second figure is the return |
| same, NMS -> ACC2 (10.10.99.22) | 40, 40, 40 lost | 35–45 s | The data-centre block is single-attached to CORE2 e1/0: management to the DC, AAA, syslog and NTP is lost until CORE2 is back and OSPF 99 has converged. This is the documented single attachment; PC3 (VLAN 50, master CORE1) 0 lost |
| Node stop of HQ-CORE1 (same timing), PC3 -> 192.0.2.200 | seq 11–52 (42 s), 12–54 (43 s), about 40 s | 40–45 s | CORE1 is the only edge-attached core (single attachment): Internet is out until CORE1 boots and re-forms OSPF/default. Basis: outage = time CORE1 is down + about 10 s (OSPF and default re-formed); 40–45 s with the drill's 31 s stop window |
| same, PC1 -> 10.10.50.103 (VLAN 50 failover to CORE2) | 11–13 + 48,49 (3+2), 11–14 (4), run 1 3 | 3–5 s | VRRP master-down |
| same, PC2 -> 192.0.2.200 (VLAN 20) | 44, 40, 40 lost (seq 8–47 in three runs) | 40–45 s | Same cause as PC3: CORE1 is the only edge-attached core, so every user loses the Internet until CORE1 is back, whatever VLAN or VRRP master |
| same, NMS -> ACC2 | 0 lost (all runs) | 0 | The DC path is on CORE2 |

Recovery: nodes return to their roles after the preempt delay; no manual step needed. After a whole-lab wipe all 18 nodes booted in about 115 s and the start state returned.

## Answers to Analysis Questions

Q1. TK3 first (its fix prevents copying faulty AAA lines to the edge in CR3), then TK2, then TK1; CR1 depends on TK1's F1 (the NAT list must cover the guest VLAN or guests leave untranslated); CR3 depends on TK3 and on the MGMT design; CR2 builds on a working edge. Any order is acceptable if the dependencies are respected and justified.
Q2. TK1: after fixing F2, the VLAN 20 traffic reaches EDGE1 and dies untranslated (F1 masked behind the routing fault); exposed by `traceroute` past EDGE1 and `show ip nat translations`. TK2: after fixing one of F3/F4 the red status clears, but the other uplink is still broken; exposed by pulling the working uplink (V3). TK3: after fixing F5, the failure changes from refused authentication to refused authorization (F6); exposed only after the radius deadtime lapses.
Q3. CR1: 0 lost pings for existing users (110/110) using `allowed vlan add`; CR2: 0 lost, IPv4 BGP uptime continued; CR3: 0 lost, BGP uptime kept; NAT list edits are followed by `clear ip nat translation *` after the ACL edit, so stale translations built before the change are dropped (a few seconds of new sessions only); TK fixes: PC2 recovers within about 4 s after F1/F2 are fixed. Student answers must quote their own measured values within the 5-ping limit.
Q4. The edge translates traffic from the user, server and guest VLANs (10/20/50/30) that leaves e0/0 (inside e0/1, pool 192.0.2.1 with overload); it routes in the global table: ISP default, campus prefixes by OSPF 1, the Internet default into OSPF; and in the MGMT table: only OSPF 99 routes learned from CORE1 over Ethernet0/1.99 (management hosts 10.10.99.0/24, 10.50.50.0/24). Management traffic is never translated because it never enters the global table: it is in the MGMT VRF, the sub-interface is not a NAT interface, and the ACL lists only user networks.

Debrief: (a) the RIB filter does not keep the default out of the DC because a distribute-list filters only the local RIB installation, not the LSA; the default still floods to area 50, so the DC still receives it and only CORE2 itself lacks it. (b) ACC2's users never noticed TK2 because VLANs 10/20 forward on both uplinks; only the management VLAN depends on the two broken parts. (c) TK3's symptom changed half-way because authentication and exec authorization are separate method lists, and the server was marked dead until the first fix made it answer.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-18 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a), net-tools, radius, syslog, unmanaged_switch |
