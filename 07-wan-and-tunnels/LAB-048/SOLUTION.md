# LAB-048 — Solution

## Summary

Extension lab (X, G2) on the WAN full environment (stages W0 to W2, `environments/WAN/`). The student connects BR1 and BR2 to HQ over the Internet with GRE tunnels and OSPF (R1), shows that BR1's static provider routes work as a backup through longest match alone (R2), adds IKEv2/IPsec protection to the running tunnels (R3), filters HQ-WAN1's Internet circuit (R4), sizes the overlay (R5) and documents the result (R6). Blueprint mapping: 2.2.b (tunnels, IPsec, overlay MTU), 3.2.b (multi-area OSPF over the overlay, ABR on HQ-WAN1, inter-area routes beating the provider /16), 5.2.a (named extended ACL for the circuit, ICMP and IPsec keywords, logging). Reinforces 046/047 (tunnels, IPsec), 016/018 (OSPF areas), 034/037 (ACL design, hardened baseline).

Build notes (all proven in CML, details in the sections below):
1. **No GRE keepalive on protected tunnels.** `keepalive 5 3` works on the plain GRE tunnels (W1) but leaves a protected tunnel `up, line protocol is down` on iol-xe. W2 has no keepalive; OSPF dead (20 s) and DPD detect failures.
2. **The W2 ACL admits only 203.0.113.131 and .133** (the two branch Internet addresses). The provider /29s are needed only for the loopback-sourced tunnels of W3 (LAB-050 adds them).
3. **R5 cannot show an MTU stall:** the CML underlay is MTU 1500 and the protected tunnel's transport MTU is 1414, so the bench shows no black hole; LAB.md checks the sizing (DF boundary, clamped SYN, complete transfer) and does not promise a symptom.
4. Pure IPsec VTI is not used (it drops transit traffic on iol-xe, see LAB-047); Q3 asks about it.
5. The R4 list also permits three ICMP reply types from INET1's link address so HQ-WAN1 can ping its own provider.

## Intentional Faults

None (X lab). Platform behaviours the student can trip over are written into LAB.md: GRE keepalive on a protected tunnel, `clear crypto session` on one end (about 80 s of flapping), the brief adjacency drop when protection is added.

## Diagnosis / Methodology

No fault hunt; the working method for each requirement:
- **R1.** Start from `show ip route 10.10.10.0` on BR1 (static /16 via PE1) and from BR2's isolation (`show ip route 10.0.0.0`: nothing). Build the two GRE tunnels from e0/0 to e0/0, run OSPF on them as point-to-point with area 21/22 and put branch LANs, loopbacks and (BR1) the management VLAN in the same areas, LAN interfaces passive. Evidence: HQ-WAN1 is the ABR with Tunnel21 in area 21 and Tunnel22 in area 22, so the branch /24s are intra-area on HQ-WAN1 (`O 10.21.10.0/24 [110/110] via 10.250.21.21, Tunnel21`, `O 10.22.10.0/24`): the ABR is attached to those areas and holds their LSDB. The branches are in a different area from the HQ networks (area 0), so they see the HQ /24s as `O IA` (`type inter area`), carried into the branch areas as type-3 (summary) LSAs by the ABR; no `area range` summarisation is configured. Rule: an ABR sees routes of its attached areas as intra-area; a router in another area sees them as inter-area. Test with a new loopback on BR2 (`Loopback50 10.22.50.1/24`, `ip ospf 1 area 22`): HQ-PC1 pings it at once. On HQ-WAN1 the prefix appears as `O 10.22.50.1/32`, not /24: OSPF advertises a loopback as a host route (loopback network type) unless `ip ospf network point-to-point` is set on it. It is still reachable; the /32 is expected.
- **R2.** BR1 holds `10.10.0.0/16` static (AD 1) and `10.10.10.0/24` OSPF inter-area (`O IA`, AD 110, metric 120). Longest match chooses the /24 whatever the AD; the /16 only matters when the /24 is gone. In the other direction HQ-WAN1 holds `10.21.0.0/16` static (redistributed to CORE1 as E2) and the OSPF /24s from BR1 (intra-area `O` there, since HQ-WAN1 is the ABR); the same rule applies. A traceroute before and after the cable pull is the proof (provider hops 100.64.x.x only after the pull).
- **R3.** Rule out the pure VTI first (see LAB-047). Build the IKEv2/IPsec objects on all three routers while the tunnels are still plain GRE (nothing changes yet), then add `tunnel protection ipsec profile VPN-PROF` to the existing tunnel interfaces, last the ACL. Plausible wrong paths: re-creating the tunnels (changes addressing and OSPF config, longer outage), adding `keepalive` (tunnel line protocol goes down: `show interfaces tunnel 21` says `Tunnel linestate evaluation down - keepalive down`, IKEv2 SA is READY, `%CRYPTO-4-RECVD_PKT_NOT_IPSEC ... prot=47` on HQ-WAN1 once a minute), protecting only one end first (the other end's plain GRE packets are dropped with the same log message until both ends are protected).
- **R4.** Build the list from the traffic the design needs: IKE UDP 500, NAT-T UDP 4500, ESP (protocol 50, not 47 once protected), NTP, ICMP. Test from PROV-INET1 and read the hit counters and the log.
- **R5.** `show interfaces tunnel 21` gives `Tunnel transport MTU 1414` (protected; plain GRE 1476). IP MTU 1400 therefore fits with 14 bytes spare. Test with DF pings from a router and a SYN capture.

## Solution Configuration

Order: R1 on all three routers, check; crypto objects on all three; tunnel protection on all four tunnel ends; the ACL last. (No keepalive anywhere. A student who added `keepalive 5 3` in R1 removes it with `no keepalive` on all four ends in R3.)

HQ-WAN1:
```
interface Tunnel21
 description to BR1-RTR1 Tunnel21
 ip address 10.250.21.1 255.255.255.0
 ip mtu 1400
 ip tcp adjust-mss 1360
 ip ospf network point-to-point
 ip ospf hello-interval 5
 ip ospf dead-interval 20
 ip ospf cost 100
 ip ospf 1 area 21
 tunnel source Ethernet0/0
 tunnel mode gre ip
 tunnel destination 203.0.113.131
interface Tunnel22
 description to BR2-RTR1 Tunnel22
 ip address 10.250.22.1 255.255.255.0
 ip mtu 1400
 ip tcp adjust-mss 1360
 ip ospf network point-to-point
 ip ospf hello-interval 5
 ip ospf dead-interval 20
 ip ospf cost 100
 ip ospf 1 area 22
 tunnel source Ethernet0/0
 tunnel mode gre ip
 tunnel destination 203.0.113.133
```
BR1-RTR1 (BR2-RTR1 mirrors it: Tunnel22, 10.250.22.22/24, area 22, `Loopback0` and `Ethernet0/1` in area 22, passive Ethernet0/1; destination 203.0.113.129):
```
interface Tunnel21
 description to HQ-WAN1 Tunnel21
 ip address 10.250.21.21 255.255.255.0
 ip mtu 1400
 ip tcp adjust-mss 1360
 ip ospf network point-to-point
 ip ospf hello-interval 5
 ip ospf dead-interval 20
 ip ospf cost 100
 ip ospf 1 area 21
 tunnel source Ethernet0/0
 tunnel mode gre ip
 tunnel destination 203.0.113.129
interface Loopback0
 ip ospf 1 area 21
interface Ethernet0/2.10
 ip ospf 1 area 21
interface Ethernet0/2.99
 ip ospf 1 area 21
router ospf 1
 passive-interface Ethernet0/2.10
 passive-interface Ethernet0/2.99
```
R3, on all three routers (identical objects):
```
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
crypto ipsec transform-set TS-AES esp-aes 256 esp-sha256-hmac
crypto ipsec profile VPN-PROF
 set transform-set TS-AES
 set ikev2-profile IKEV2-PROF
```
Then on each tunnel end (HQ-WAN1 Tunnel21 and Tunnel22, BR1-RTR1 Tunnel21, BR2-RTR1 Tunnel22):
```
interface TunnelNN
 tunnel protection ipsec profile VPN-PROF
```
R4, HQ-WAN1:
```
ip access-list extended WAN1-INET-IN
 permit udp host 203.0.113.131 host 203.0.113.129 eq isakmp
 permit udp host 203.0.113.133 host 203.0.113.129 eq isakmp
 permit udp host 203.0.113.131 host 203.0.113.129 eq non500-isakmp
 permit udp host 203.0.113.133 host 203.0.113.129 eq non500-isakmp
 permit esp host 203.0.113.131 host 203.0.113.129
 permit esp host 203.0.113.133 host 203.0.113.129
 permit udp host 203.0.113.131 host 203.0.113.129 eq ntp
 permit udp host 203.0.113.133 host 203.0.113.129 eq ntp
 permit icmp host 203.0.113.131 host 203.0.113.129 echo
 permit icmp host 203.0.113.131 host 203.0.113.129 echo-reply
 permit icmp host 203.0.113.131 host 203.0.113.129 unreachable
 permit icmp host 203.0.113.131 host 203.0.113.129 time-exceeded
 permit icmp host 203.0.113.131 host 203.0.113.129 packet-too-big
 permit icmp host 203.0.113.133 host 203.0.113.129 echo
 permit icmp host 203.0.113.133 host 203.0.113.129 echo-reply
 permit icmp host 203.0.113.133 host 203.0.113.129 unreachable
 permit icmp host 203.0.113.133 host 203.0.113.129 time-exceeded
 permit icmp host 203.0.113.133 host 203.0.113.129 packet-too-big
 permit icmp host 203.0.113.128 host 203.0.113.129 echo-reply
 permit icmp host 203.0.113.128 host 203.0.113.129 unreachable
 permit icmp host 203.0.113.128 host 203.0.113.129 time-exceeded
 deny   ip any any log
interface Ethernet0/0
 ip access-group WAN1-INET-IN in
```
(The finished state equals `environments/WAN/W2/`.)

R6 expected content (outline): Tunnel21/22 GRE over IPsec, 10.250.21.0/24 and 10.250.22.0/24, hub .1, protected by `VPN-PROF` (IKEv2 AES-256/SHA-256/DH 14, ESP AES-256/SHA-256, PSK, DPD 10 2 on-demand); areas 0/21/22 with HQ-WAN1 as ABR, branch LANs passive; backup by longest match (/24 OSPF vs /16 static, both directions) with no tracking; the ACL entries and the reason for each (IKE, NAT-T, ESP, NTP, ICMP incl. PMTUD, provider replies, final logged deny).

## Verification

All outputs captured on the build lab (CML 2.10.0, iol-xe 17.16.1a) unless marked (derived).

**Start state (W0):** BR1-PC1 to HQ-PC1 via `10.21.10.1, 100.64.21.0, 100.64.10.1, 10.10.255.96`; BR1-PC1 and BR2-PC1 to 198.51.100.200 OK (PAT, BR2 translated to 203.0.113.133); BR2-PC1 to HQ-PC1 and BR1-PC1 100% loss; HQ-PC1 to BR1-PC1 OK, to BR2-PC1 loss; HQ-WAN1 OSPF neighbour only HQ-CORE1; the re-imported lab gave the same results.

**R1 / V1 / V2 (W1):** HQ-WAN1 OSPF FULL on Tunnel21 and Tunnel22; BR1 route to 10.10.10.0/24 is OSPF inter-area via Tunnel21 (metric 120) with `10.10.0.0/16 static via 100.64.21.0` as the less-specific entry. BR2-PC1 to HQ-PC1 traceroute: `10.22.10.1, 10.250.22.1, 10.10.255.96, 10.10.10.101`; BR1-PC1 to BR2-PC1 and HQ-PC1 to BR2-PC1/10.255.22.1 OK. New `Loopback50 10.22.50.1/24` (`ip ospf 1 area 22`) on BR2: HQ-PC1 pings it at once; HQ-WAN1 shows it as `O 10.22.50.1/32` (loopback host-route behaviour, see R1), and the branch /24s are intra-area `O` there.

**R2 / V3:** before the pull BR1-PC1 to HQ-PC1: `10.21.10.1, 10.250.21.1, 10.10.255.96`; HQ-PC1 to BR1-PC1: `10.10.255.97, 10.250.21.21`. After the pull (BR1 e0/0 and INET1 e0/1 shut down, WAN1 adjacency gone): BR1-PC1 to HQ-PC1 `10.21.10.1, 100.64.21.0, 100.64.10.1, 10.10.255.96` (ping 3/3); HQ-PC1 to BR1-PC1 `10.10.255.97, 100.64.10.0, 100.64.21.1`. BR1 `show ip route 10.10.10.0` answered by `10.10.0.0/16 static via 100.64.21.0`; HQ-WAN1 by `10.21.0.0/16 static via 100.64.10.0`. After `no shutdown` both return to the tunnel.

**R3 / V4 (W2):** BR1/BR2 OSPF FULL on the tunnels again (cost 100, hello 5 / dead 20); `show interfaces tunnel 21` on HQ-WAN1: `Tunnel protection via IPSec (profile "VPN-PROF")`, `Tunnel transport MTU 1414` (plain GRE: 1476). `show crypto ipsec sa interface Tunnel21`: identity `203.0.113.129/32/47` to `203.0.113.131/32/47` (protocol 47 host pair), `transform: esp-256-aes esp-sha256-hmac`, `#pkts encaps/decaps` rising. Capture on the BR2-INET1 link: tunnel traffic only `203.0.113.129 <-> 203.0.113.133 proto=50 ESP`, no protocol 47, no inner addresses; after `clear crypto session` on BR2: IKE_SA_INIT (exchange 34, 2 messages), IKE_AUTH (35, 2 messages), informational (37), then ESP; NTP UDP 123 stays in the clear.

**R4 / V5:** counters: esp 5/9 matches, ntp 66/22, deny 9. From INET1 pings to 203.0.113.129 from Lo0 (198.51.100.200), with the default source and from 203.0.113.128: all 0/3 (`U`); log: `%SEC-6-IPACCESSLOGDP: list WAN1-INET-IN denied icmp 198.51.100.200 -> 203.0.113.129 (8/0)`. `ping 203.0.113.129 source Ethernet0/0` from BR1 and BR2: 100%. Tunnels, OSPF and BR2-PC1 to HQ-PC1 keep working; branch PCs still reach 198.51.100.200.

**R5 / V6:** DF ping from BR2-RTR1 (`source Ethernet0/1`) through the tunnel: size 1400 3/3, size 1401 0/3. `nc` 300000 bytes BR2-PC1 to HQ-PC1:5001: `wc -c` 300000; tcpdump at HQ-PC1: SYN with `mss 1360` (HQ-PC1 itself offers 1460, so the clamp is proven). The underlay is MTU 1500, so there is no stall to see without conditioning.

**V8:** BR2-RTR1 and BR1-ACC1 (through BR1's PAT) reach `sys.peer` (`*~203.0.113.129`) after about 30 minutes; BR1-RTR1 too, but only after its poll was reset by the many e0/0 shutdowns (reach 0 for a long time). `show snmp user`: nmsuser SHA/AES128 on the routers, SHA only on BR1-ACC1 (unchanged baseline).

## Failure / Recovery Behaviour

Clock: device log timestamps of the same host (cable pull: BR1 `%LINK-5-CHANGED ... administratively down` is the trigger, which lags the configuration by about 2 s); silent failure: `send log 1 TRIG-..` marker on BR2 just before the REST link stop (values include a 1-3 s marker-to-stop gap). Method names (never mixed): **cable pull** = `shutdown` of BR1 e0/0 and of PROV-INET1 e0/1 (both ends; the student shuts BR1 e0/0 only, which is equivalent for HQ-WAN1 because it cannot see INET1's port state: (derived)); **silent failure** = CML link stop of BR2-INET1. Every run was restored and OSPF FULL re-confirmed before the next.

| Scenario (trigger, end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| W2 cable pull BR1-INET1: BR1 link-down log to BR1 Tunnel21 down | 5.3 / 1.7 / 3.2 s | 1-7 s | interface down is local and immediate; the first run includes DPD/log lag |
| W2 cable pull: BR1 link-down to HQ-WAN1 OSPF dead on Tunnel21 | 14.3 / 14.5 / 14.3 s | 12-21 s | dead 20 s counted from the last hello (up to 5 s old), minus the 2 s trigger lag |
| W2 cable pull: to HQ-WAN1 Tunnel21 line down (DPD) | 19.1 / 21.3 / 16.5 s | 15-25 s | DPD: 10 s without inbound traffic, then retries every 2 s until the peer is declared dead, after OSPF traffic stops |
| W2 restore: `no shutdown` to HQ-WAN1 Tunnel21 up / OSPF FULL | FULL 15.1 / 9.9 s; third run tunnel up 2.1 s (FULL line not captured) | 8-17 s to FULL | IKE_SA_INIT/AUTH, then adjacency (hello 5 s) |
| W1 (plain GRE, keepalive 5 3) cable pull: HQ-WAN1 OSPF dead / tunnel line down | 16.5 / 16.9 / 13.8 s; 16.5 / 17.7 / 13.8 s | 13-18 s | keepalive 5 3 gives 15 s, as OSPF dead; pulled side 2.0 / 2.0 / 2.0 s; restore 10.2 / 9.1 / 7.5 s |
| W2 silent failure BR2-INET1: BR2 OSPF dead | 21.2 / 21.3 / 20.5 / 22.9 / 19.8 / 18.3 s | 17-24 s | dead 20 s plus the marker gap |
| W2 silent failure: HQ-WAN1 OSPF dead | 20.4 / 21.2 / 19.5 / 22.0 / 19.0 / 18.4 s | 17-24 s | same |
| W2 silent failure: Tunnel22 line down (BR2; HQ-WAN1) | BR2 27.6 / 24.0 / 26.7 / 29.3 / 26.1 / 21.4 s; WAN1 23.4 / 28.1 / 22.2 / 24.7 / 21.6 / 25.0 s | 20-31 s | DPD (10 s without inbound traffic, then retries every 2 s until the peer is declared dead) starts only when traffic stops, after the first OSPF dead |
| W2 silent failure restore: link start to FULL / tunnel up | 6.9 / 11.8 / 4.7 s (S4-S6; S1-S3 not marked) | 4-15 s | IKE restart plus hello 5 s |

Findings: in both W2 failure types the routing protocol detects first (OSPF dead 14-23 s), the tunnel line follows through DPD (16-30 s); the pulled side knows within seconds because the tunnel source interface goes down. The route state during the pull is in R2 above. Without keepalive (the protected design) the up/up tunnel of a silently failed peer is never trusted for forwarding for longer than OSPF dead; the 20 s dead timer is the practical failover time.

## Answers to Analysis Questions

1. **Q1.** Route lookup uses the longest prefix first: BR1 has the OSPF /24 (inter-area, AD 110) and the static /16 (AD 1); the /24 wins whatever the AD. When the tunnel adjacency is gone, only the /16 remains and the provider carries the traffic; the same holds at HQ-WAN1 for 10.21.0.0/16 against the branch /24s. Evidence: R2 tables. It breaks if the overlay-learned route stops being more specific than the static: summarising the branch LANs into the /16 at the ABR (equal length, then AD 1 wins), or replacing the static with a /24, or giving the overlay the /16 only. A floating static or tracking is not needed here because the prefixes differ in length. If the backup had the same length as the overlay route (a /24 static), AD would decide, and the static would have to float above OSPF's 110.
2. **Q2.** The tunnel endpoints' underlay prefixes (the 203.0.113.x Internet addresses, in particular HQ-WAN1's 203.0.113.129 and the branches' 203.0.113.131/.133) and any route that leads to them. If a router learns the tunnel destination through the tunnel itself, the tunnel's next hop recurses into itself: `%ADJ-5-PARENT` then `%TUN-5-RECURDOWN`, the tunnel flaps (observed in LAB-046: cycle 65-75 s). In this design the Internet interfaces are not in OSPF and HQ-WAN1 redistributes only `10.21.0.0/16` (the prefix list in route-map `PROV-ROUTES`) from its statics, never the 0/0 or the Internet /31s.
3. **Q3.** Order: crypto objects first (nothing changes in forwarding), `tunnel protection` added to the existing tunnel interfaces (interface, addresses and OSPF configuration untouched; both ends protected, then the adjacency re-forms within one hello cycle after the SAs are up; the brief drop and `%CRYPTO-4-RECVD_PKT_NOT_IPSEC ... prot=47` while one end is protected first are expected), the ACL last, so IKE/ESP/NTP are never filtered before they are permitted. The routing design survives because the tunnel is the same interface; only the encapsulation of its packets changes (GRE then ESP, `Tunnel transport MTU` 1476 to 1414). A pure IPsec VTI (`tunnel mode ipsec ipv4`) has less overhead (no 24-byte GRE header; ESP tunnel mode directly), has no GRE keepalives (failure detection by routing protocol and DPD only; on a protected GRE tunnel on this platform GRE keepalive fails anyway) and, on iol-xe, drops all transit traffic (LAB-047), so it was not an option here.
4. **Q4.** PMTUD relies on ICMP unreachable (fragmentation needed) and packet-too-big. If the circuit's list drops them, a sender that sets DF never learns the path limit and large transfers stall without any error. The list permits them (and time-exceeded for traceroute, echo for troubleshooting). The wildcard PSK means one secret for all peers and an IKE profile that matches any identity: anyone who learns the key from one branch can authenticate as a branch to HQ-WAN1, and a compromised branch exposes every tunnel's authentication; the ACL's source restriction limits who may try. Per-peer keys (keyring entries per peer address or identity) or certificates remove this.
5. **Q5.** BR2's only path is its Internet line to HQ-WAN1, so when HQ-WAN1's circuit fails both overlays lose their hub: BR2 loses HQ and BR1 (BR1 still reaches HQ through the provider service, but BR1 to BR2 traffic also needs the hub). To keep BR2 working it needs a second hub path (a second headend or a second HQ Internet circuit with a second tunnel and a routing preference, previewed in LAB-053) or a provider line of its own.
6. **Q6.** The time service: branch NTP to 203.0.113.129 (UDP 123) is authenticated but in the clear (capture), as are the IKE negotiation messages themselves (by design), and the PAT'd Internet traffic of the branches (not site-to-site). To encrypt time, point the clients at HQ-WAN1's loopback 10.255.10.41 (reached through the overlay) and drop the NTP entries from the list (derived, not tested).
7. **Q7.** On a cable pull, the pulled side detects instantly (tunnel source interface down, 2-6 s) while the far side learns first from OSPF dead (14-15 s), then DPD marks the tunnel line down (16-22 s). On a silent failure OSPF dead is first on both sides (18-23 s), DPD follows (21-30 s). Recovery 4-16 s. The ranges are in the table above.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a) |
