# LAB-067 — Solution

## Summary
Foundation build of a LISP control plane (blueprint 2.3.a, first exposure; the SD-Access fabric analog, stage FAB F0). Students build a map server/resolver on FAB-MSMR1 and two xTRs, register two endpoint subnets that the OSPF underlay never learns, and see the pull model work: registration, map-request/map-reply, a map-cache with a 24 h positive TTL, a negative map-reply for an unregistered EID, and UDP 4341 data encapsulation with the instance-ID in the LISP header. The failure test shows that an established flow survives the loss of the mapping system until its cache entry is lost. Platform: iol-xe (control and data plane work; the data plane is LISP, not VXLAN: VXLAN is LAB-068). No intentional faults (F lab). Stage written: `environments/FAB/F0/`.

## Intentional Faults
None (F lab).

## Diagnosis / Methodology
Not a troubleshooting lab. Expected student path for the start state: PC1 pings its gateway but not PC2; `show ip route vrf CORP` on XTR1 has only C and L; `show ip route 10.60.11.0` says "% Subnet not in table" (global); no `router lisp`. The routing protocol cannot help, so the destination must be found by mapping, not routing.

## Solution Configuration
FAB-MSMR1:
```
router lisp
 site AST-XTR1
  authentication-key ROUTEKEY123
  eid-record instance-id 4097 10.60.10.0/24
 site AST-XTR2
  authentication-key ROUTEKEY123
  eid-record instance-id 4097 10.60.11.0/24
 service ipv4
  map-server
  map-resolver
```
FAB-XTR1 (FAB-XTR2 identical except `database-mapping 10.60.11.0/24 locator-set RLOC`):
```
router lisp
 locator-set RLOC
  IPv4-interface Loopback0 priority 1 weight 100
 service ipv4
  itr map-resolver 10.255.60.1
  itr
  etr map-server 10.255.60.1 key ROUTEKEY123
  etr
 instance-id 4097
  service ipv4
   eid-table vrf CORP
   database-mapping 10.60.10.0/24 locator-set RLOC
```
Applied as one config block per device; nothing was refused. Instance-ID 4097 with `eid-table vrf CORP` is accepted on iol-xe 17.16. FAB-SPINE1 and the PCs are unchanged.

## Verification
**R1/R2/V1** (MSMR1, captured on a fresh import; `#` = registration over reliable transport; the `show lisp site` family prints a deprecation banner and still works):
```
FAB-MSMR1# show lisp site
Site Name      Last      Up     Who Last              Inst     EID Prefix
               Register         Registered            ID
AST-XTR1       00:00:21  yes#   10.255.60.11:24996    4097     10.60.10.0/24
AST-XTR2       00:00:19  yes#   10.255.60.12:51980    4097     10.60.11.0/24
FAB-MSMR1# show lisp site detail | include Allowed|Registration errors|mismatch
Allowed configured locators: any
      Allowed locators mismatch: 0
```
PC1 and PC2 ping each other (V2; see R3 below).

**V3** RIB unchanged after the solution, on XTR1: `C 10.60.10.0/24`, `L 10.60.10.1/32` only; `show ip route 10.60.11.0` gives `% Subnet not in table`. XTR2 shows only its own C and L. Right after start the map-cache holds only a permanent-looking `0.0.0.0/0 ... via static-send-map-request, Negative cache entry, action: send-map-request` line (cosmetic; the IOS XE default, present at all times).

**R3/V4** (`clear lisp instance-id 4097 ipv4 map-cache` works, no confirm prompt). PC1 `ping -c 6 -i 1 -W 1 10.60.11.102` right after the clear:
```
64 bytes from 10.60.11.102: seq=2 ttl=42 time=4.997 ms   (seq 0 and 1 lost)
6 packets transmitted, 4 packets received, 33% packet loss
XTR1# show lisp instance-id 4097 ipv4 map-cache 10.60.11.0/24
10.60.11.0/24, uptime: 00:00:06, expires: 23:59:53, via map-reply, complete
  State: complete, last modified: 00:00:06, map-source: 10.255.60.12
  Locator       Uptime    State  Pri/Wgt     Encap-IID
  10.255.60.12  00:00:06  up       1/100       -
```
Lost packets: 2 with both caches empty in three runs (the request direction and, because XTR2's cache is also empty, the reply direction both need a map-request); 1 when only one side's cache was empty (clear on XTR1 only, or XTR2 only); the first ping of a fresh start also loses one to ARP. Positive TTL 24 h (`expires: 23:59:53`).

**R3 capture** (V5; CML capture on SPINE1-XTR1, filter `udp port 4341 or udp port 4342`; the points below describe what the capture shows. The CML UI capture dissects both ports as LISP).
- Capture count: with both map-caches cleared, one ping run holds several Map-Requests (158 to 170 bytes, repeated while the entry is incomplete; 4 requests and 2 replies, one reply per direction, in one run), not just "one request and one reply". Look for at least one request and its reply.
- Map-Request: an Encapsulated Control Message (LISP type 8). Outer IP 10.255.60.11 (XTR1 Loopback0) to 10.255.60.1 (the map resolver), UDP 4342 to 4342, TTL 255, frame 170 bytes; the inner header carries the EID asked (10.60.11.102).
- Map-Reply: LISP type 2, **direct from the ETR**: 10.255.60.12 to 10.255.60.11, UDP 4342 to 4342, frame 94 bytes (the map server forwarded the request to the registered ETR, which answers the requesting ITR itself).
- Data packet: frame 134 = 14 Ethernet + 20 outer IP + 8 UDP + 8 LISP + 84 inner IP. Outer IP total length 120, **source 10.60.255.3** (the egress interface address, not the Loopback0 RLOC), destination 10.255.60.12 (the ETR's RLOC). UDP source port 1027 (dynamic, varies), destination 4341. LISP flags 0x48 (L=1 locator-status-bits present, I=1 instance-ID present), nonce/map-version bytes 000000, instance-ID 4097 (0x001001) in bytes 4-6 of the header, LSB 0x01. Inner IP 10.60.10.101 to 10.60.11.102, proto 1 (ICMP), length 84. Overhead = 20 + 8 + 8 = **36 bytes**. Hex offsets in the Ethernet frame: outer IP 14, UDP 34 (ports at 34-37), LISP header 42 (flags 42, instance-ID 46-48, LSB 49), inner IP 50. Return traffic from XTR2 has outer source 10.60.255.5.
- Teaching note: because the outer source is the interface address, replies to it rely on SPINE1 knowing the connected /31 networks (they are in OSPF via `ip ospf 1 area 0`).

**R4/V6** PC1 ping 10.60.12.1: 3 sent, 100% loss. XTR1 map-cache afterwards:
```
10.60.12.0/22, uptime: 00:00:03, expires: 00:14:56, via map-reply, forward-native
  Negative cache entry, action: forward-native
  State: forward-native, last modified: 00:00:03, map-source: 10.60.255.0
XTR1# show lisp instance-id 4097 ipv4 statistics | include Negative records
    Negative records in/out:                        2/0
```
The map server answered with the covering unregistered prefix (a /22 here) as a negative map-reply; TTL about 15 min, because no site is configured for that space (a prefix that is configured but unregistered gets a 1-min negative entry instead, see the failure test). `forward-native` means the ITR does not encapsulate but forwards the packet natively; in VRF CORP there is no route for it, so it is dropped. With a proxy ETR / `use-petr` this is exactly where traffic leaving the fabric would be handed off (LAB-069).

## Failure / Recovery Behaviour
Method: **silent failure**, `tools/cml-rest.sh link stop` on SPINE1 e0/0 to MSMR1 e0/0 (interfaces stay up/up). MSMR1's console stayed reachable. Recovery: `link start`.
- An established PC1 to PC2 ping continued with no loss for the 26 s observed after the stop (map-cache valid). After `clear lisp ... map-cache` on XTR1 during the outage the ping failed from the clear on (XTR1 cache `10.60.11.102/32 ... incomplete`, via data-signal; no map-reply).
- `yes#` became `yes` at the stop (the reliable transport session was lost). The established session holds the registration: it is not refreshed periodically while the session is up (Last Register age kept growing: 5:49 at +26 s) and expires about 186 s only after the session is lost. The 24 h figure is the positive map-cache TTL, not a registration lifetime.

| Scenario (trigger -> end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| `link stop` -> both sites `no` / `never` on MSMR1 (poll every 2-3 s, host clock) | 187 s (3 s poll), 186, 186, 186 | 180-190 s | 3 min registration lifetime plus poll granularity |
| `link start` -> both sites `yes#` again (age at observation vs host clock) | about 6 s, 4-6 s, about 6 s, about 6 s | 5-10 s | TCP reconnect plus registration |
| `link start` -> first successful PC1 to PC2 ping reply (PC loop `ping -c1 -W1; sleep 1`, `date +%s`) | about 50 s (coarse), 6 s, 54 s, 54 s | 5-65 s (runs 6/54/54/12 s) | 1-min negative entry for a configured but unregistered site prefix (measured in LAB-071 R2: `expires: 00:00:56`) plus 5-10 s registration |

Why the first reply can wait up to a minute: after the MS expired the registrations, XTR1 asked and received a negative map-reply (`10.60.11.0/24 ... via map-reply, forward-native`, seen at +12 s in run 4); that entry blackholes traffic until it times out (about 1 min: a configured but unregistered site prefix gets a 1-min negative entry, unlike the 15 min of space no site claims) and the next request succeeds. The first reply therefore varies from about 6 s to about 55 s (runs 6, 54, 54 and 12 s) depending on whether a negative entry was cached and how much of its minute remained when the link returned; expect any value in 5-65 s, not one number. Run 2 was fast because the old incomplete entry expired just after `link start`. State restored by wiping MSMR1/XTR1/XTR2 (LISP was never saved) and re-running the start checks.

## Answers to Analysis Questions
1. **Q1.** An ITR looks up the destination in the VN's routing table first; LISP encapsulates only when there is no route (the LISP-created `0.0.0.0/0` send-map-request entry then triggers resolution). A covering route (default or summary) in VRF CORP makes the edge forward natively, so the ITR forwards the packet natively along that VRF route (to wherever it points, or drops it) and never sends a map-request.
2. **Q2.** Push: every edge carries every route (100 sites: 100 prefixes, more with hosts) and learns of changes by flooding; no first-packet loss. Pull: an edge holds only its own database-mapping and the entries for flows it uses; the MS holds all registrations (state concentrated in one place); the first packet(s) to a new destination are lost or delayed (1-2 pings here); positive entries live 24 h; negative entries about 15 min for space no site claims (measured, R4) and 1 min for a configured but unregistered site prefix. Suits a campus with very many endpoints because the edge table scales with active flows, not with the number of endpoints, and moves are handled by re-registering.
3. **Q3.** Traffic that already had a valid map-cache entry survived (no map-request needed); new destinations and cleared entries failed because no reply came. Registrations expire after about 3 min, after which even new flows fail. After recovery the registrations return in 5-10 s, but a negative entry cached while the registration was gone can keep blackholing traffic for up to about a minute.
4. **Q4.** LISP: outer IP + UDP 4341 + 8-byte LISP header (flags, nonce/map-version, 24-bit instance-ID, LSB) = 36 bytes; the instance-ID identifies the VN, and the receiving ETR picks the VRF from it. GRE (LAB-046): outer IP + 4-byte GRE header (flags, protocol type; optional key/sequence) = 24 bytes; GRE has no standard VN field (a key can be used), and no control plane: peers are configured. LISP adds UDP (outer source port varies with the inner flow), so the underlay can hash it.
5. **Q5.** A moving host re-registers through its new edge (dynamic EID registration); the MS then updates the mapping (and the old edge is notified by a map-notify / SMR), so other edges' cached entries are refreshed. In this build the subnet-based `database-mapping` would have to become a dynamic EID (per-host) mapping; not built here.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a) |
