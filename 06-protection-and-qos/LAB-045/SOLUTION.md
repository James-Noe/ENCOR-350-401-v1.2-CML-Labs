# LAB-045 — Solution

## Summary

Troubleshooting lab (T, G1) on the derived HQ lite H3 + EDGE min E3 + DC min stage (11 nodes). Four tickets, six faults (F6 is the VLAN-map retrieval from 041), built on four earlier modules: OSPF NSSA default origination (3.2.b, X-StubNSSA), summaries and route filters (3.2.b), EtherChannel consistency (3.1.b), OSPFv3 network types (IPv6), VLAN maps (5.2.a, 041), with NAT (3.3.b) and AAA (5.1.b) as the red herrings and the shift's normal access path. Three faults sit on one device (HQ-CORE1), two of them in parallel on TK2 (F2/F3), and fixing only one leaves a latent weakness: that is Q2/Q3. TK1 now needs two changes in series (F1 on HQ-CORE1, F6 on HQ-ACC1): that is Q7. Blueprint: 3.2.b:T, X-StubNSSA:T, 3.1.b:T, IPv6:T, 5.2.a:T, 3.3.b:R, 5.1.b:R.

## Intentional Faults

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-CORE1 | OSPFv2 `area 10 nssa` without `default-information-originate` (OSPFv3 keeps it) | TK1: DIST1/2 have no IPv4 default, so VLAN 10 loses IPv4 Internet; VLAN 20 (gateway on CORE1, area 0) is fine |
| F2 | HQ-CORE1 | `ip prefix-list NO-LAB-RANGE seq 5 deny 10.10.56.0/21 le 32` (should be /22), used by `distribute-list prefix … in` | CORE1 does not install 10.10.60.0/24 (DMZ) from OSPF |
| F3 | HQ-CORE1 | `area 10 range 10.10.0.0 255.255.0.0` (should be 255.255.240.0) | discard route 10.10.0.0/16 → Null0 beats the default: 10.10.60.150 is black-holed at CORE1 (TK2, together with F2) |
| F4 | HQ-DIST2 | Et0/1 `switchport trunk allowed vlan` differs from Po1 | TK3: member suspended, `Po1(SU) Et0/0(P) Et0/1(s)` on both DISTs |
| F5 | HQ-EDGE1 | Et0/1 `ospfv3 network broadcast` (CORE1 side point-to-point) | TK4: OSPFv3 adjacency FULL but no routes: CORE1 has no ::/0, EDGE1 has no HQ /64s |
| F6 | HQ-ACC1 | VLAN map FLOOR-GUARD sequence 20 carries `match ip address FLOOR-INTERNAL` (`10 permit ip any 10.0.0.0 0.255.255.255`) instead of being a bare `action forward`; sequence 10 (FLOOR-PEERS, `action drop log`) and `vlan filter FLOOR-GUARD vlan-list 10` are as designed | TK1: every VLAN 10 IPv4 packet to a non-10/8 destination hits the map's implicit drop on ACC1, before it reaches the gateway; intranet, ARP and IPv6 are untouched; VLAN 20 is not filtered |

Fault logic: F1 and F6 are in series behind TK1: each alone keeps VLAN 10 off the IPv4 Internet, so fixing either first leaves PC1 failing (proven both orders, below). F2 and F3 are in parallel (either fix restores TK2). F1 is OSPFv2-only: IPv6 for VLAN 10 breaks only at CORE1 (no ::/0) until F5 is fixed, which is what splits TK1 from TK4. Red herrings: NAT table holds only VLAN 20 entries (VLAN 10 packets never reach EDGE1); `EDGE-IN-V4` and CoPP show no hits for HQ traffic; HSRP and VRRP healthy; OSPF neighbours all FULL; RADIUS logins work.

## Diagnosis / Methodology

- **TK1.** PC1 traceroute 192.0.2.200: hop 1 10.10.10.2 (DIST1), then `!H`; PC2 reaches the same host. Gateway is fine (PC1 reaches VLAN 20/50), NAT table has VLAN 20 entries only and no ACL deny counters. DIST1 `show ip route 0.0.0.0` → `% Network not in table`; `show ip ospf database nssa-external` is empty; CORE1 `show ip ospf` area 10 is an NSSA with no default origination: F1.
- **TK1, second cause (F6).** After F1 is fixed DIST1 has `O*N2 0.0.0.0/0` yet PC1 still fails: traceroute to 192.0.2.200 is silent even at hop 1 (an internal traceroute shows 10.10.10.2 at hop 1), so the packet dies before the gateway. DIST1 `ping 192.0.2.200 source Vlan10` and `ping 198.51.100.64` succeed, so the path beyond the gateway is good. ACC1 `show vlan filter` shows FLOOR-GUARD on VLAN 10; `show vlan access-map FLOOR-GUARD` shows sequence 20 forwarding only what FLOOR-INTERNAL matches; `show ip access-lists FLOOR-INTERNAL` counts PC1's intranet pings (112 matches in the build) and not its Internet pings. `%VLMAPLOG` stays silent (the drop clause is not involved: the implicit drop does not log). Reverse order: with F6 fixed and F1 open, PC1 traceroute stops at hop 2 `!H` from 10.10.10.2 (no default on the DIST).
- **TK2.** PC2 traceroute 10.10.60.150: stops at 10.10.20.2 (CORE1, `!H`). EDGE1 reaches the DMZ and Internet clients reach 192.0.2.130 (published service), so server, HSRP, NAT and ACL are fine. CORE1 `show ip route 10.10.60.150` → `10.10.0.0/16 … via Null0 (metric 16777215)` (F3); the DMZ stub is in the OSPF database but not in the RIB, and `show ip prefix-list NO-LAB-RANGE` shows /21 (F2).
- **TK3.** Both members up/up (CDP); no STP inconsistency; `show etherchannel summary` `Et0/1(s)`; `%ETC-5-CANNOT_BUNDLE2: Et0/1 is not compatible with Po1 … (vlan mask is different)`; `show interfaces trunk` shows the allowed-list difference (F4).
- **TK4.** Hosts have IPv6 and RA defaults; EDGE1 reaches the Internet host in IPv6 (eBGP v6 up). CORE1 `show ipv6 route ::/0` → `% Route not found` though the neighbour is FULL; `show ospfv3 interface Ethernet0/1` shows BROADCAST on EDGE1 against point-to-point on CORE1 (F5).
- **Overlap.** Fix F2 first (specific route returns), verify the V4 check still fails (the /16 discard remains), then fix F3. Fixing only F3 makes the DMZ depend on the default route (shown by the V3 drill).
- **Wrong fixes** (each tried once, all fail V4/V5): static default on DIST1 (`S* 0.0.0.0/0`); `nssa no-summary` (DIST1 loses the `O IA` routes); static 10.10.60.0/24 on CORE1; `no channel-group 1` on the suspended member (peer shows `Et0/1(w)`, capacity stays halved); an IPv6 static default. F6 wrong fixes: `no vlan filter FLOOR-GUARD vlan-list 10` (PC1 reaches the Internet, but PC1 <-> PC2 on VLAN 10 now passes: isolation lost, V4 fails; reapplied afterwards); a host-only entry `5 permit ip any host 192.0.2.200` in FLOOR-INTERNAL (the Internet host answers, PC1 -> 198.51.100.64 is 100% loss: V1 provider-address clause fails, V4 fails). A RACL on the DIST Vlan10 SVIs instead of the map was not run on the lab: its result (it cannot stop PC-to-PC traffic inside VLAN 10, which never reaches the SVI) is derived from LAB-041 Q1.
- **V6 access.** SSH needs a source in MGMT-HOSTS: open sessions from VLAN 99 SVIs of DIST1/DIST2/ACC1 or from CORE1 (`ssh -vrf MGMT -l netadmin 10.10.99.11`, source 10.10.99.2). EDGE1 and DC-RTR1 cannot source from 10.10.99.x directly, so hop to them from CORE1/DIST. Consoles also work with `netadmin`.

## Solution Configuration

```
! HQ-CORE1
router ospf 1
 no area 10 nssa
 area 10 nssa default-information-originate
 no area 10 range 10.10.0.0 255.255.0.0
 area 10 range 10.10.0.0 255.255.240.0
no ip prefix-list NO-LAB-RANGE seq 5 deny 10.10.56.0/21 le 32
ip prefix-list NO-LAB-RANGE seq 5 deny 10.10.56.0/22 le 32
! HQ-ACC1 (F6; accepted alternative: a new bare forward sequence after 20)
ip access-list extended FLOOR-INTERNAL
 20 permit ip any any
! HQ-DIST2
interface Ethernet0/1
 switchport trunk allowed vlan 10,20,50,99
! HQ-EDGE1
interface Ethernet0/1
 ospfv3 network point-to-point
```

The old prefix-list sequence must be removed first (a duplicate sequence aborts the whole block).

## Verification

Captured on the solved lab (all six fixes):

- V1: PC1 and PC2 ping 192.0.2.200 3/3, 198.51.100.64 3/3 and 2001:db8:f001:200::200 3/3 (immediately after the F6 fix, no protocol wait). With the host-only F6 fix 198.51.100.64 is 100% loss.
- V2: PC1 and PC2 ping 10.10.60.150 3/3; HQ-SRV1 → PC1 ok. From PROV-ISP1 `telnet 192.0.2.130 80 /source-interface Loopback200` → `Open`, then an HTTP error reply from httpd (for example `400 Bad Request` or `408 Request Timeout` after an idle telnet; any HTTP reply proves the TCP 80 service is reachable); `EDGE-IN-V4` line 250 `(1 match)`; NAT `tcp 192.0.2.130:80 10.10.60.150:80 192.0.2.200:32940`. ICMP to 192.0.2.130 from the Internet is denied by the edge ACL (correct, only TCP 80 is published).
- V4: CORE1 `show run | section router ospf 1` → `area 10 nssa default-information-originate`, `area 10 range 10.10.0.0 255.255.240.0`, `distribute-list prefix NO-LAB-RANGE in`; OSPFv3 AF `area 10 nssa default-information-originate`. `show ip route`: `O*E2 0.0.0.0/0 via 10.10.255.65`, `O 10.10.0.0/20 is a summary, Null0`, `O 10.10.60.0/24 via 10.10.255.65`; `show ip route 10.10.56.0 255.255.252.0` → `% Subnet not in table`; no static routes. DIST1 `O*N2 0.0.0.0/0` plus `O IA` 10.10.20.0, .50.0, .60.0/24, and `::/0` `NSSA extern 2`.
- V4 (floor isolation): ACC1 `show vlan filter` -> FLOOR-GUARD on VLAN 10; map seq 10 FLOOR-PEERS `drop log`, seq 20 FLOOR-INTERNAL `forward`; FLOOR-INTERNAL `10 permit ip any 10.0.0.0 0.255.255.255 (38)`, `20 permit ip any any (98)`. Peer clause proven once in the build (ACC1 e0/3 temporarily moved to VLAN 10, PC2 as 10.10.10.102): PC1 <-> PC2 100% loss with `%VLMAPLOG-6-ICMP: vlan 10 (port Et1/0) denied icmp 10.10.10.101 -> 10.10.10.102`; both reach .1 and .2 (PC1 also .3). FLOOR-PEERS deny lines count non-peer traffic (a deny line means no match in a map, not a drop). IPv6 under the IP-only map: PC1 reaches 2001:db8:10:20::102 with F6 present; Internet IPv6 fails until F5 is fixed, then 2/2 ok, so the TK1/TK4 split stands.
- V5: both DISTs `Po1(SU) LACP Et0/0(P) Et0/1(P)`.
- V6: DIST1 `%SEC_LOGIN-5-LOGIN_SUCCESS: Login Success [user: netadmin] [Source: 10.10.99.2]`; DC-AAA1 log `Auth: (0) Login OK: [netadmin]`, `ACCT Start user=netadmin nas=10.10.99.11 session=00000003`, `ACCT Stop`.
- Causality: F2 only fixed → CORE1 `10.10.60.0/24 ospf 1 via 10.10.255.65`, DMZ pings from PC1/PC2 3/3, but `10.10.0.0/16` still via Null0 (V4 fails). F3 only fixed → `10.10.0.0/20 is a summary … Null0`, PC2 reaches the DMZ via the default, PC1 still lacks IPv4 default (F1); the V3 drill then fails (below). F1 fixed → DIST1 `O*N2 0.0.0.0/0` within one poll; PC1 -> 192.0.2.200 still 100% loss until F6 is fixed (F6 only: DIST1 has no default, PC1 `!H` at hop 2). F6 fixed (`20 permit ip any any`) → immediate. F4 fixed → `Po1(SU) Et0/0(P) Et0/1(P)` within 5 s. F5 fixed → CORE1 `::/0 ospf 1, metric 10`; EDGE1 learns the HQ /64s as inter-area.

## Failure / Recovery Behaviour

Cable pull = `shutdown` on both ends of HQ-EDGE1 / PROV-ISP1 Ethernet0/0, with all fixes in place and `ping -i 1` running from PC1 and PC2 to 10.10.60.150: 0 packets lost across four pulls (last seq 375 on both, awk gap check). Measured: the default is gone within about 2 s of the pull, because the eBGP session drops with the interface; the ~13-16 s figure is the IP SLA track, which matters only for the static backup.

| Scenario (trigger, end condition) | Runs (s) | Documented range | Basis |
|---|---|---|---|
| Both-end `shutdown` of the ISP link -> EDGE1 `show track 10` "Reachability is Down" (poll 2 s) | 13, 13, 13, 16 (v1.0 build: 16, 14, 16) | 10-20 s | SLA frequency 5 s, `delay down 5` |
| Both-end `shutdown` -> CORE1 `show ip route 0.0.0.0` `% Network not in table` (poll 1 s) | 2, 2 (first poll on two pulls) | within about 2 s | eBGP drops with the interface (link-down is immediate; derived for the bound) |
| `no shutdown` both ends -> CORE1 has the OSPF default again | 48, 50, 48, 48 (v1.0 build: 46, 50, 43) | 40-55 s | track `delay up 30` plus BGP and SLA |

After the pull CORE1 has no default (0 DMZ loss in four pulls with F2 fixed) (`% Network not in table`) but keeps `10.10.60.0/24 ospf 1`. With F3 fixed only (F2 latent) the same pull gave PC2 → 10.10.60.150 0/3: the DMZ rode the default route. That is the V3 weakness.

DC-AAA1 node stop (silent failure for the RADIUS server): DIST1 logs `%RADIUS-4-RADIUS_DEAD` and `%RADIUS-3-ALLDEADSERVER: Group RADGRP`; the local `admin` login succeeds about 11 s into the attempt (`LOGIN_SUCCESS [user: admin]`); `netadmin` fails. After `node start` (BOOTED in 31 s in v1.0, 11 s in the v1.1 re-run, `test aaa group RADGRP netadmin netpass legacy` succeeds again; with the node stopped it reports no authoritative response after 19 s) `netadmin` works again and DC-AAA1 logs `ACCT Start … session=00000007`.

## Answers to Analysis Questions

Q1. TK1: PC2 (VLAN 20) works and the NAT table/ACL counters show no problem, so NAT and the edge are not the cause; the DIST has no default (F1), and once that is fixed PC1's traceroute is silent at hop 1 while an internal one is not, which points at filtering before the gateway (F6). TK2: the server is reachable from EDGE1 and from the Internet by its public address, so the server/NAT/ACL are fine; traceroute stops at the core. TK3: both links are up and STP is clean, so it is bundling. TK4: IPv6 works on EDGE1 and eBGP v6 is up, so the ISP side is fine; the core lacks ::/0.
Q2 (debrief). TK1 and TK2 share a device: both are on HQ-CORE1 (F1 in the NSSA line, F2/F3 in the filter and the range); TK1 also has F6 on HQ-ACC1. TK2 itself has two parallel causes (F2 and F3): either fix restores reachability, so fix one, re-test both tickets and V4 (`show ip route` for the /16 discard and the filter), then the other, so one fix does not hide the second.
Q3 (debrief). Fixing only F3 (or only the prefix-list) restores the DMZ, but with F3 alone the DMZ depends on the default: a provider-link pull (V3 drill) black-holes it. Found by running the V3 cable-pull test and by checking that the DMZ route is a specific OSPF route.
Q4. TK3 (capacity, no user impact, recurrence with a config compare) and TK1/TK2 (a change-control gap: "area 10 NSSA" and the weekend clean-up changed several devices) are problem-record candidates; TK4 is a single-link mismatch worth a record only if the compare tool did not catch it.
Q5. Hand-over example: TK1 F1 (NSSA without default origination on the ABR) fixed with `area 10 nssa default-information-originate`, and F6 (FLOOR-GUARD forward sequence limited to 10/8) fixed with `20 permit ip any any` in FLOOR-INTERNAL; TK2 F2 prefix-list /21→/22 and F3 range /16→/20; TK3 F4 allowed-list mismatch on the DIST2 member; TK4 F5 OSPFv3 network type on the edge link. Checks: V1–V6, cable pull, accounting for `netadmin`.
Q6. The central account gives per-user accounting and revocation; a shared local account does neither. With the central server down, the local account is the only way in, which is why it exists; its use must be recorded and the secret changed afterwards.
Q7 (debrief). TK1: F1 (HQ-CORE1) and F6 (HQ-ACC1) in series. After the first fix PC1 still fails; the evidence is the DIST default present but traceroute silent at hop 1 (F6 open), or no default on the DIST with the traceroute dying at hop 2 `!H` (F1 open). F6 stays hidden until F1 is fixed because neither shows in the other's evidence.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-16 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a), radius |
