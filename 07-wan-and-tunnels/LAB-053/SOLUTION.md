# LAB-053 — Solution

## Summary

An Expansion (X) lab. Students add a second headend path for BR2 through the protected Internet edge of the E3 project: HQ-WAN1's DMZ address 10.10.60.41 is published as 192.0.2.140 with a static NAT on both edges, BR2 builds Tunnel122 (GRE over IPsec) to it from Loopback203, the edges get the two narrowest ACEs the protocols allow, the control-plane policy is proven not to need a change, and the path is proven from counters, a capture and the DC's flow records.

Blueprint mapping: 2.2.b (GRE over IPsec, IKEv2, NAT-T) · 3.3.b (static NAT on two edges) · 4.2 (FNF records on NMS1) · 5.2.a (edge ACL, narrowest exception) · 5.2.b (CoPP: transit vs punted traffic). Designed discovery: **tunnel-mode `VPN-PROF` does not work across the NAT** (see Diagnosis); the working design is a transport-mode IPsec profile on Tunnel122 only, a deliberate exception recorded in `environments/EDGE/E4/README.md`.

## Intentional Faults

None (X lab). The start state is E3 plus the WAN Internet path, with no backup tunnel, no NAT for 10.10.60.41 and no edge exception. The only "trap" is design-level: the tunnel-mode profile of the other tunnels fails across the NAT.

## Diagnosis / Methodology

1. **Discovery of the edge policy.** Bring up a plain Tunnel122 first (source e0/3, destination 192.0.2.140) with no edge change: nothing answers. BR2's first IKE_SA_INIT reaches the active edge and is logged: `%SEC-6-IPACCESSLOGP: list EDGE-IN-V4 denied udp 203.0.113.163(500) -> 192.0.2.140(500), 1 packet`, with `260 deny ip any any log` counting. That names the exact source, destination and ports for the ACEs. (Raw evidence when the static NAT existed but the ACEs did not: also `denied gre 203.0.113.163 -> 192.0.2.140`.)
2. **NAT.** Without the static mapping 192.0.2.140 does not exist on the edges; the mapping must be identical on both edges and without ports (any port the peer uses, 500 then 4500, must pass). `show ip nat translations | include 140` shows the static entry plus the two UDP flows.
3. **The tunnel-mode failure (kept as the teaching point).** With `VPN-PROF` on Tunnel122 and both the NAT and the ACEs in place, NAT detection works (`Host is located NAT inside` on HQ-WAN1, `NAT-T is detected  outside` on BR2) and the float to UDP 4500 happens, but IKE_AUTH fails: `debug crypto ikev2 error` (with `logging buffered 64000 debugging`) shows `There was no IPSEC policy found for received TS` and `Construct Notify Payload: TS_UNACCEPTABLE`; Tunnel122 stays line protocol down. Cause (in one sentence: the tunnel-mode child SA's selector is the pair of GRE endpoint addresses each end believes in, and across the static NAT the two ends hold different pairs, whereas in transport mode the selectors are the outer addresses each end actually sees, which the NAT translation makes consistent): the protected traffic is GRE between the two tunnel endpoints, and the ends name different GRE endpoints (HQ-WAN1 believes 10.10.60.41 to 203.0.113.163, BR2 203.0.113.163 to 192.0.2.140), so the traffic selectors do not match across the translation. Ruled out: the edge (the exchange reaches the peer), the PSK or proposal (the same IKEv2 profile authenticates Tunnel22), the ACL (251/252 count).
4. **Transport mode (RFC 7296 §2.23.1, RFC 3948).** In transport mode across NAT the traffic selectors are the addresses each end actually sees (RFC 7296 §2.23.1: the receiver sees the translated outer address), so the SA matches; RFC 3948 defines the UDP 4500 encapsulation of ESP that carries it; an IPsec profile `VPN-PROF-NAT` with transform set `mode transport` is used on Tunnel122 only. Tunnel22 (no NAT) keeps `VPN-PROF` (tunnel mode). The profile exists on both ends; OSPF becomes FULL on Tunnel122.
5. **Edge ACL, narrowest form.** The tunnel peers use 500 then 4500 at both ends (BR2 is not behind a NAT), so both ACEs match the source address, source port, destination address and destination port. No ESP line: after NAT-T detection ESP rides inside UDP 4500 (Q2). The final `260 deny ip any any log` stays; ACEs go between 250 and 260 on **both** edges (EDGE2 carries the path after a failover).
6. **CoPP.** Take counter deltas of `show policy-map control-plane` on the active edge over equal windows: idle, IKE re-negotiation (shut/no shut of Tunnel122 on both ends), and 100 denied UDP 4500 probes (`traceroute 192.0.2.140 source Loopback201 numeric probe 100 timeout 1 ttl 30 30 port 4500`). Only the last moves a class (class-default, the punted copies of the logged denies). The permitted tunnel is transit traffic and is never punted, so PM-COPP stays unchanged.
7. **Flow evidence.** Run `tshark -i eth0 -a duration:100 -d udp.port==2055,cflow ...` on DC-NMS1 in the background, then bounce Tunnel122 (a UDP 4500 flow is exported only when it ends). Timing: FM-EDGE uses inactive 15 s / active 1800 s, so the flow ends 15 s after its last packet. Start tshark first, shut Tunnel122 on both ends and keep it down at least 30 s (a shorter bounce can re-use the cache entry and export nothing), then restore it; use a capture of at least 60 s. Records also appeared with a capture of 5 s, bounce, then 40 s. `cflow.inputint` 1 = Ethernet0/0, 3 = Ethernet0/2.

## Solution Configuration

HQ-EDGE1 and HQ-EDGE2 (identical):
```
ip nat inside source static 10.10.60.41 192.0.2.140
ip access-list extended EDGE-IN-V4
 251 permit udp host 203.0.113.163 eq isakmp host 192.0.2.140 eq isakmp
 252 permit udp host 203.0.113.163 eq non500-isakmp host 192.0.2.140 eq non500-isakmp
```

HQ-WAN1:
```
ip route 203.0.113.163 255.255.255.255 10.10.60.1
crypto ipsec transform-set TS-AES-TRANSPORT esp-aes 256 esp-sha256-hmac
 mode transport
crypto ipsec profile VPN-PROF-NAT
 set transform-set TS-AES-TRANSPORT
 set ikev2-profile IKEV2-PROF
interface Tunnel122
 ip address 10.250.122.1 255.255.255.0
 ip mtu 1400
 ip tcp adjust-mss 1360
 ip ospf network point-to-point
 ip ospf hello-interval 5
 ip ospf dead-interval 20
 ip ospf cost 500
 ip ospf 1 area 22
 tunnel source Ethernet0/3
 tunnel mode gre ip
 tunnel destination 203.0.113.163
 tunnel protection ipsec profile VPN-PROF-NAT
```

BR2-RTR1:
```
crypto ipsec transform-set TS-AES-TRANSPORT esp-aes 256 esp-sha256-hmac
 mode transport
crypto ipsec profile VPN-PROF-NAT
 set transform-set TS-AES-TRANSPORT
 set ikev2-profile IKEV2-PROF
interface Tunnel122
 ip address 10.250.122.22 255.255.255.0
 ip mtu 1400
 ip tcp adjust-mss 1360
 ip ospf network point-to-point
 ip ospf hello-interval 5
 ip ospf dead-interval 20
 ip ospf cost 500
 ip ospf 1 area 22
 tunnel source Loopback203
 tunnel mode gre ip
 tunnel destination 192.0.2.140
 tunnel protection ipsec profile VPN-PROF-NAT
```

Optional (debug of the discovery step): `logging buffered 64000 debugging` and `debug crypto ikev2 error` on HQ-WAN1/BR2-RTR1, set back afterwards. The solution is as tested (re-applied on a fresh import: tunnel up within the 45 s before the first check). Cross-check: `environments/EDGE/E4/` holds the finished device files. R6 is a document: the answer is an updated protection matrix with a row "UDP 500/4500 from 203.0.113.163 to 192.0.2.140: permitted, both edges" and a statement that HQ-WAN1 is a shared dependency of both tunnels.

## Verification

Captured on a fresh import after applying the solution, trimmed:
```
HQ-WAN1# show ip ospf neighbor | include FULL
10.255.10.1  FULL/ -  Ethernet0/2
10.255.22.1  FULL/ -  10.250.122.22  Tunnel122
10.255.22.1  FULL/ -  10.250.22.22   Tunnel22
HQ-WAN1# show crypto ikev2 sa | include READY
2   10.10.60.41/4500      203.0.113.163/4500   none/none  READY
1   203.0.113.129/500     203.0.113.133/500    none/none  READY
HQ-WAN1# show interfaces Tunnel122 | include line protocol|Tunnel transport
Tunnel122 is up, line protocol is up
  Tunnel transport MTU 1418 bytes
BR2-RTR1# show crypto ikev2 sa detailed | include Local id|Remote id|NAT-T
  Local id: 203.0.113.133   Remote id: 203.0.113.129   NAT-T is not detected      (Tunnel22)
  Local id: 203.0.113.163   Remote id: 10.10.60.41     NAT-T is detected  outside (Tunnel122)
BR2-RTR1# show crypto ipsec sa interface Tunnel122 | include in use|remote ident
   remote ident (addr/mask/prot/port): (192.0.2.140/255.255.255.255/47/0)
        in use settings ={Transport UDP-Encaps, }
BR2-RTR1# ping 10.250.122.1 size 1400 df-bit repeat 2   -> !! (2/2)
BR2-RTR1# ping 10.250.122.1 size 1401 df-bit repeat 2   -> .. (0/2)
BR2-RTR1# show ip route 10.10.10.0 | include via
  * 10.250.22.1, from 10.255.10.41, via Tunnel22          (metric 120, primary preferred)
HQ-EDGE1# show ip nat translations | include 140
gre 192.0.2.140:0     10.10.60.41:0    203.0.113.163:0     203.0.113.163:0
udp 192.0.2.140:500   10.10.60.41:500  203.0.113.163:500   203.0.113.163:500
udp 192.0.2.140:4500  10.10.60.41:4500 203.0.113.163:4500  203.0.113.163:4500
--- 192.0.2.140       10.10.60.41      ---                 ---
HQ-EDGE1# show ip access-lists EDGE-IN-V4 | include 25[0-2] |260
    250 permit tcp any host 192.0.2.130 eq www
    251 permit udp host 203.0.113.163 eq isakmp host 192.0.2.140 eq isakmp (2 matches)
    252 permit udp host 203.0.113.163 eq non500-isakmp host 192.0.2.140 eq non500-isakmp (27 matches)
    260 deny ip any any log (1 match)
HQ-EDGE2# show ip nat statistics | include Total
Total active translations: 2 (2 static, 0 dynamic; 0 extended)
```

V1 (build, cable pull of HQ-WAN1 e0/0 and PROV-INET1 e0/0): BR2 `10.10.10.0/24 via 10.250.122.1 Tunnel122` metric 520; traceroute BR2-PC1 to HQ-PC1 `10.22.10.1, 10.250.122.1, 10.10.255.96, 10.10.10.101` (primary: `10.250.22.1` as hop 2); IKEv2 SA `203.0.113.163/4500 <-> 192.0.2.140/4500 READY` seen from BR2, edge ACL 251/252 counting. DF test: 1400 passes, 1401 fails; no 40-byte adjustment is needed (NAT-T adds 8 bytes on top).

V3 (R2): real IKE from 203.0.113.163 with source ports 500 then 4500 hits 251/252. Probes (`traceroute 192.0.2.140 source <lo> numeric probe 3 timeout 1 ttl 30 30 port <p>`, edge answers `!A`) from Loopback201 (203.0.113.161), from Loopback203 with a random source port, and from PROV-ISP1 Loopback200 (192.0.2.200): `260 deny ip any any log` 125 to 134 (+9); `%SEC-6-IPACCESSLOGP: list EDGE-IN-V4 denied udp 203.0.113.161(49253) -> 192.0.2.140(500), 1 packet` and `denied udp 203.0.113.163(49257) -> 192.0.2.140(501)`; 251/252 unchanged. E3 matrix sample: `telnet 192.0.2.130 80 /source-interface Loopback200` from PROV-ISP1 connects (`HTTP/1.1 408 Request Timeout`); PCs reach 192.0.2.200.

V4 (R3), deltas on HQ-EDGE1 (the active edge) with `show clock` at both snapshots: idle 75 s: CM-ROUTING +436, CM-MONITOR +15, CM-MGMT +7, class-default +19. IKE re-negotiation (shut/no shut both ends; SA Active Time 64 s afterwards) in a 60 s window: ROUTING +350, MONITOR +12, MGMT +9, class-default +15, every `exceeded` +0. 100 denied probes to UDP 4500 from 203.0.113.161: ACL `260` +100 (16 to 116), EDGE1 class-default +124 in 101 s (idle about +25), CM-UNDESIRABLE and CM-ICMP +0; EDGE2 +24 (not on the path). Conclusion: PM-COPP unchanged; the logged copies of refused packets, not the tunnel, load class-default.

V5 (R4), DC-NMS1 `tshark -i eth0 -a duration:100 -d udp.port==2055,cflow -Y cflow.srcaddr -T fields ...` with Tunnel122 bounced: exporter 10.10.254.5 (EDGE1), `cflow.inputint 1` (Et0/0): 203.0.113.163 to 192.0.2.140 UDP 4500 to 4500, 36 packets; `cflow.inputint 3` (Et0/2): 10.10.60.41 to 203.0.113.163 UDP 4500 to 4500, 38 packets; the UDP 500 pair 2 packets each. Cache: `show flow monitor FM-EDGE cache format table | include 203.0.113.163|192.0.2.140|10.10.60.41`: outside addresses at Et0/0 (before NAT), inside addresses at Et0/2.

V9 (toolkit): CML capture on the BR2 Et0/0 to PROV-INET1 Et0/2 link over 25 s with Tunnel122 bounced: `480 203.0.113.133 > 203.0.113.129 ESP` and `479` reverse (Tunnel22, protocol 50, no UDP, no GRE); backup pair `15 192.0.2.140 > 203.0.113.163 udp 4500>4500 ESP-in-UDP` / `14` reverse, `6`/`6` IKE_AUTH/INFORMATIONAL with the non-ESP marker on 4500, `2`/`2` udp 500>500 (the first two IKE_SA_INIT messages only; the peers then float to 4500). The peer on the BR2 link is 192.0.2.140 (BR2 never sees 10.10.60.41). CLI alternative without a capture: `show crypto ipsec sa` on BR2 for the primary peer 203.0.113.129 shows no NAT-T/UDP-encaps flag (native ESP), while for peer 192.0.2.140 it shows `encaps: ... UDP-Encaps` / NAT-T 4500, and `show crypto ikev2 sa detailed` reports `NAT-T is not detected` (Tunnel22) versus `NAT-T is detected  outside` (Tunnel122).

V10: BR2 `*~203.0.113.129 st 3 reach 214`, `Clock is synchronized, stratum 4`; HQ-EDGE1 `*~10.50.50.1` reach 377, at about 70 min uptime.

## Failure / Recovery Behaviour

Clocks: router clock = CML host clock; loss runs use BR2-PC1 to HQ-PC1 ping at 1/s (`seq=` numbers = seconds), `UNTIL` values are the scripted polling clock from the config block (they overestimate by up to the poll interval). Cable pull = `shutdown` on both ends. Silent failure = `tools/cml-rest.sh link stop`. Node stop = `node stop` after `write memory` on HQ-WAN1 and BR2. All runs return to the pre-trigger steady state before the next.

| Scenario (trigger, end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| Cable pull of HQ-WAN1 e0/0 + INET1 e0/0; end = first ping reply on the backup path (lost pings) | lost 9, 3, 2, 10, 9 (CLI poll 11, 5, 5, 14, 11 s) | 2-25 s (V1 limit 30 s) | BR2 learns HQ-WAN1's new LSA over the already FULL Tunnel122 (no dead wait), spread = LSA/SPF; upper bound dead 20 s + SPF (derived) |
| Failback (both `no shutdown`); end = BR2 route to 10.10.10.0 via Tunnel22 | 6, 40, 11, 11 s (two more unverified: 21, 16 s); no ping lost on failback in any run | 5-60 s (V1 limit 90 s) | IKE re-establishment + OSPF hello 5 / dead 20 on Tunnel22; the 40 s run |
| Silent failure, `link stop` of HQ-WAN1-INET1; end = pings flowing again (lost pings) | 18, 18, 16 | 14-25 s (V7 limit 30 s) | OSPF dead interval 20 s on Tunnel22 is the detector (no DPD faster), 4 s margin each way |
| Failback after `link start`; end = route via Tunnel22 | 9, 35, 2 s (poll clock), no loss | 2-60 s | IKE retrying + OSPF |
| R5: cable pull of HQ-EDGE1 e0/0 + PROV-ISP1 e0/0 while on the backup path; end = ping flow resumed (lost pings) | 1, 1, 1 | 0-5 pings (V6 limit 20 s) | ISP2 learns the route; EDGE2 carries the traffic; tunnel SAs kept |
| same; end = track 10 Down on EDGE1 after BGP down | 7.4, 5.9, 9.0 s | 5-15 s | SLA/track timers (E3 measured 5-13 s) |
| same; end = HSRP Active again on EDGE1 after the restore (`no shutdown` both ends) | 46, 43, 47 s | 35-60 s | track Up +39-41 s then preempt (E3 measured 32-48 s) |
| R5 SAs | same SPIs 0xDCC136F2 / 0x53E1CA85 before and after, Active Time 392 s then 464 s, 626 s, 758 s (continuous) | kept | outer addresses never change: both edges hold the same static mapping without ports |
| ISP-B loss (HQ-EDGE2 e0/0 + PROV-ISP2 e0/0 shut) while the backup runs through EDGE1 | 55 pings, no gap | no loss | EDGE2 not on the path |
| Node stop of HQ-WAN1; end = BR2 OSPF dead on Tunnel22 / Tunnel122 | 18.5 / 20.2; 17.1 / 16.7; 17.2 / 17.4 s | 14-25 s | dead interval 20 s |
| same; end = Tunnel line protocol down | 23.8 / 23.3; 23.7 / 23.2; 23.7 / 23.8 s | 20-30 s | IPsec session teardown after the neighbours |
| same; end = route back after `node start` (config from NVRAM) | route already present at the first poll 25-26 s, route age 13-14 s (about 11-13 s after the start command) | 10-30 s | boot + IKE + OSPF |

During the HQ-WAN1 stop BR2 has no route to 10.10.10.0 ("Subnet not in table") from the dead timer until the node is back: both headend paths end on HQ-WAN1, a documented single point of failure (Q6). Edge-pull detail: ISP1 learns 192.0.2.128/26 from ISP2, INET1 keeps sending .140 traffic to ISP1 (AD 1 static), ISP1 hands it to ISP2 and EDGE2, which holds the same static mapping; HQ-WAN1's replies go to the VIP, so EDGE1 (still Active for 6-9 s) forwards them over e0/3 to EDGE2 (OSPF default) and EDGE2 translates 10.10.60.41 to 192.0.2.140.

## Answers to Analysis Questions

**Q1.** In IKE_SA_INIT each peer sends NAT-D payloads (hashes of address and port as it sees them). HQ-WAN1 sees BR2's hash unchanged but its own address differ from what BR2 hashed, so it reports `Host is located NAT inside`; BR2 reports `NAT-T is detected  outside`. Both then move from UDP 500 to UDP 4500: the capture shows only the first two messages on 500, then IKE on 4500 with a 4-byte non-ESP marker, and ESP carried inside UDP 4500 (`in use settings ={Transport UDP-Encaps, }`; 15/14 ESP-in-UDP packets in 25 s).

**Q2.** Permitted: UDP 500 and UDP 4500 from 203.0.113.163 (source ports 500 and 4500) to 192.0.2.140, on both edges; nothing else is needed. Once NAT-T is in use, ESP is encapsulated in UDP 4500, which 252 permits. A permit for protocol 50 would be needed if no NAT were detected on the path (the peers then send native ESP, as Tunnel22 does), or if NAT-T were disabled; the UDP-only design also shows why a bare `permit esp` would be broader than needed (and would not cover a NAT'd path).

**Q3.** DMZ in OSPF area 0 would let the edges form an adjacency with HQ-WAN1 over the DMZ, making HQ-WAN1 a transit router between the core and the edges (and a route-learning path for the Internet side): traffic could be steered through the encrypting router, and the tunnel's destination route could be learned through the DMZ/tunnel (recursion). The DMZ is reached by a host route only.

**Q4.** The NAT rewrites only the outer (tunnel endpoint) header of already encapsulated traffic. The protected traffic is GRE between the tunnel endpoints, and the users' traffic is routed into the tunnel before it reaches any NAT. A crypto-map tunnel (047) protects user subnets and must be exempted from the NAT rule that would otherwise rewrite those packets before encryption; there is none here (the static mapping matches only 10.10.60.41, and the users' PAT list never sees tunnel traffic).

**Q5.** Normal case: EDGE1 (Active, BGP to ISP1) carries it; with EDGE1 or ISP-A lost, EDGE2/ISP-B carries it; ISP-B loss is invisible while EDGE1 is active. The SAs survive because the outer addresses (203.0.113.163 and 192.0.2.140) never change and both edges hold the same static mapping without port translation: same SPIs and a continuous Active Time were measured (one ping lost). A peer behind a dynamic mapping on one device (BR3 behind a provider PAT in MS-3) would present a new source address/port from another translator after a failover, so the IKE/IPsec sessions would be re-established and DPD/NAT-T keepalives would decide the outage.

**Q6.** It survives: loss of the primary Internet circuit (or its provider, silent or cable-pull), loss of either HQ provider or either edge router. It does not survive HQ-WAN1 failing, because both tunnels terminate on it (BR2 loses HQ entirely until it is back, dead timer 14-25 s then no route). Removing it requires a second headend router (a second HQ WAN router with its own DMZ address and tunnel, or an HA pair), so that the two paths no longer share a device.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-25 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), net-tools, radius, syslog, unmanaged_switch |
