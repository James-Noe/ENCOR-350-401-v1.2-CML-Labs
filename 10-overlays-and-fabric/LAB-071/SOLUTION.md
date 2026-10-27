# LAB-071 — Solution

## Summary
Troubleshooting an overlay fabric by plane. Three independent faults sit behind two tickets: F3 (the border's return path into the overlay) is common to both, F1 (mapping-system registration) is TK1's second cause, F2 (fusion leaking) is TK2's second cause. Each ticket is a series of two faults, so fixing the first one found closes neither. The teaching point of F3 is that BDR1's routing table is identical in the working and the broken state: the Null0 /23 anchor is the BGP origination, and the `map-cache <block> map-request` line next to it is what tells LISP "this block lives in the overlay, ask the mapping system". Without it the anchor is the only match for a fabric host, so BDR1 discards the replies without ever sending a map-request (LAB-067's covering-route rule, applied on the border). Blueprint objectives: 2.3.a LISP (T), 1.3.b SD-Access interworking with traditional networks (T), 1.3.a SD-Access architecture (T), 2.2.a VRF and route leaking (T). Domains 1, 2.

## Intentional Faults
| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | FAB-XTR1 | `etr map-server 10.255.60.1 key ROUTEKEY132` (design: `ROUTEKEY123`) | MSMR1 `show lisp site`: AST-XTR1 `never`/`no`, Authentication failures counted (10 on a fresh import, 30/31 in an earlier run). XTR1 can still send (it resolves others), but nobody can find 10.60.10.0/24 or 10.60.20.0/24. TK1 printer fails (PC1 to 10.60.11.1 3/3 lost); PC2 to the badge hub 10.60.20.1 fails too (side evidence) |
| F2 | DC-FUS1 | VRF IOT: `route-target import 65010:50` removed | IOT never receives 10.50.51.0/24: BDR1 IOT session Established with 0 prefixes received (CORP receives 1); FUS1 `show ip route vrf IOT 10.50.51.0` "Subnet not in table". CORP is not affected |
| F3 | FAB-BDR1 | `router lisp`: `map-cache 10.60.10.0/23 map-request` (instance 4097) and `map-cache 10.60.20.0/23 map-request` (instance 4098) removed. The Null0 /23 anchors, the BGP `network` statements and the proxy-etr/proxy-itr roles stay | Veridian still learns both /23s (anchors keep the `network` routes), so the DC replies to BDR1; the Null0 /23 is the only match, so BDR1 never sends a map-request and discards every reply. Forward path (edge, PETR, FUS1, DNS1) works. Both VNs lose the shared services |

Fault logic: F3 is common to both tickets. TK1 = F3 + F1 (with F3 fixed BDR1 asks the mapping system for 10.60.10.101 and gets a negative reply because XTR1 is unregistered; with F1 fixed alone the reply still hits the anchor). TK2 = F3 + F2 (with F2 fixed alone DNS1 answers and the reply dies at the IOT anchor; with F3 fixed alone IOT has no route to the DC). F1 does not touch TK2 and F2 does not touch TK1. The printer test (PC1 to 10.60.11.1) fails by F1 alone and does not depend on F3.

Note on F1: a live key change on a running fabric leaves the site registered (`yes#`) while the reliable-transport session stays up; the fault shows after `clear lisp site *` or a reload, which is why the story says devices were reloaded. A fresh import always boots with the fault. After wiping MSMR1 run `clear lisp site *` after boot.

## Diagnosis / Methodology
1. Reproduce from the hosts. PC1 and PC2 ping their gateways (3/3) but not 10.50.51.53 (3/3 lost) and `nslookup erp.veridian.example 10.50.51.53` times out. PC1 to the printer 10.60.11.1 and PC2 to the hub 10.60.20.1 are 100% lost.
2. Eliminate the name service: DC-RTR1 `ping 10.50.51.53 source Ethernet0/3` 2/2; DNS1 is directly attached to DC-RTR1. The DNS query log is not visible on the console, so DNS1 receipt is shown by counters on DC-RTR1 (step 6).
3. Eliminate the underlay and DC routing: OSPF neighbours FULL, RLOC loopback pings succeed. DC-RTR1 holds 10.60.10.0/23 and 10.60.20.0/23 via 10.50.255.1; FUS1 VRF CORP holds 10.60.10.0/23 from 10.200.60.3 and VRF IOT 10.60.20.0/23 from 10.200.60.5. All BGP sessions Established. The negative map-cache entries for 10.50.51.0/24 at the edges are normal (PETR path). So the DC team's "nothing changed that matters" is true.
4. DC-RTR1 `traceroute 10.60.10.101 source Ethernet0/3` (a shared-services source the VNs can return to) passes FUS1 (10.50.255.1), reaches BDR1 (10.200.60.3) and stops with `!H`: the last answering hop is the border, which points at BDR1.
5. Mapping system: MSMR1 `show lisp site` shows AST-XTR1 `never`/`no` for 4097 and 4098; `show lisp site detail` counts authentication failures for XTR1 only. XTR1's `etr map-server` key differs from the standard: F1. The wrong cure is to change the key on MSMR1 (V4).
6. Handoff: BDR1 `show ip bgp vpnv4 vrf CORP summary` receives 1 prefix from 10.200.60.2, vrf IOT receives 0 from 10.200.60.4; FUS1 VRF IOT lacks 10.50.51.0/24 while CORP has it; `show vrf detail IOT` shows the missing import RT 65010:50: F2.
7. The border. Compare the planes on BDR1 for CORP host 10.60.10.101: `show ip route vrf CORP 10.60.10.101` is `10.60.10.0/23 static, distance 1 (connected) via Null0, Advertised by bgp 65060` (the RIB is identical with the map-cache lines present, so it cannot show F3); `show ip cef vrf CORP 10.60.10.101` is `10.60.10.0/23 attached to Null0` (the CEF/forwarding table discards); `show lisp instance-id 4097 ipv4 map-cache` and `4098` are empty; `show lisp instance-id 4097 ipv4 statistics` Map-Requests in/out 0/0 after many PC1 queries. `show lisp service ipv4` still shows PITR and PETR enabled. F3: no map-cache entry says "ask the mapping system", so the anchor wins.
8. Capture on SPINE1 e0/3 to BDR1 e0/3 (filter `udp port 4341 or udp port 4342`) while PC1 pings 10.50.51.53 is the student's evidence; the same thing was also proved with temporary ACL counters (see Verification). Expected capture content `(derived)` from those counters: UDP 4341 from XTR1 to BDR1 carrying inner 10.60.10.101 to 10.50.51.53 is present; no UDP 4341 from BDR1 to XTR1; no UDP 4342 map-request from BDR1. With F3 fixed and F1 present one map-request leaves BDR1 per lookup and the map-reply is negative `(derived)`; ACL counters showed 2 UDP 4342 map-requests out of BDR1 in that state.
9. Isolation (all measured, BDR1 map-cache cleared between states with `clear ip lisp map-cache instance-id 409x`): F3 only fixed: PC1 and PC2 to 10.50.51.53 100% lost, nslookup times out; BDR1 CEF `10.60.10.0/24 attached to Null0` (negative entry), map-cache `10.60.10.0/23 static-send-map-request` plus `10.60.10.0/24 via map-reply, forward-native, Negative cache entry`. F2 + F3: PC2 30/30 replies (6-7 ms), nslookup resolves; PC1 100% lost. F1 + F3 (F2 reverted): PC1 19/20 replies, nslookup resolves, printer reachable; PC2 100% lost. F1 + F2 fixed with F3 open: PC1 and PC2 100% lost, BDR1 CEF back to Null0.
10. Wrong fixes: (a) removing BDR1's Null0 anchors (`no ip route vrf CORP 10.60.10.0/23 Null0` and IOT, map-cache lines present): FUS1 VRF CORP and IOT lose the /23 within 2 s, DC-RTR1 loses both /23s ("Subnet not in table"), the BGP /23 is gone from BDR1, PC1 and PC2 to the DNS 100% lost and nslookup times out; restoring the two static routes brings DC-RTR1's routes back in at most 2 s and both PCs 3/3 (V6 catches this). (b) Changing the key on MSMR1 for XTR1's site (`authentication-key ROUTEKEY132`): AST-XTR1 registers within about 5 s but the two sites then use different keys (V4 fails); no timing documented. (c) A default route in a VN table on an xTR, importing CORP into IOT, or static per-host routes on BDR1 were not run `(derived)`: a covering route in a VN table makes the xTR forward natively instead of encapsulating to the PETR (LAB-067 rule), leaking CORP into IOT joins the VNs (V3), and a VN table has no RLOC path, so per-host routes do not restore encapsulation.

## Solution Configuration
```
! DC-FUS1
vrf definition IOT
 address-family ipv4
  route-target import 65010:50
! FAB-XTR1
router lisp
 service ipv4
  etr map-server 10.255.60.1 key ROUTEKEY123
! FAB-BDR1
router lisp
 instance-id 4097
  service ipv4
   map-cache 10.60.10.0/23 map-request
 instance-id 4098
  service ipv4
   map-cache 10.60.20.0/23 map-request
```
Order is free; each ticket closes only when both of its faults are fixed (F3 + F1 for TK1, F3 + F2 for TK2). Optional: `clear ip lisp map-cache instance-id 4097` (and 4098) on BDR1 to drop a lingering negative entry. Without the clear, expect up to about 60 s after F1 is fixed before TK1 passes (the negative entries for 10.60.10.x have a 60 s lifetime; measured: PC1 DNS 0/4 and printer 0/3 right after the key fix, passing about 1 min later), so wait and retest rather than assume the fix failed. No saving needed in the lab (the stored day-0 is the start state).

## Verification
Observed after all three fixes. Start state re-observed on a fresh import of the YAML (82 s to BOOTED, checks run about 3 minutes after boot): PC1 and PC2 reach their gateways 3/3; PC1 and PC2 to 10.50.51.53 3/3 lost; PC1 to 10.60.11.1 3/3 lost; PC2 to 10.60.20.1 3/3 lost; nslookup "connection timed out"; MSMR1 AST-XTR1 `never no`, Authentication failures 10; BDR1 CORP receives 1, IOT 0; CEF `10.60.10.0/23 attached to Null0`; DC-RTR1 OSPF FULL with the /23s; traceroute last hop `10.200.60.3 !H`; FUS1 VRF IOT "Subnet not in table".

End state (trimmed):
```
PC1 / PC2 -> 10.50.51.53: replies (6-7 ms); nslookup erp.veridian.example 10.50.51.53 -> Address: 10.50.51.53
   (busybox then prints "server can't find ... NXDOMAIN" for the AAAA query: harmless, the first answer counts)
PC1 -> 10.60.11.1: 3/3
V3: PC1 -> 10.60.21.102 100% loss; PC2 -> 10.60.10.101 100% loss; PC2 -> 10.255.50.5 (FUS1 loopback) 100% loss; PC1 -> 10.50.51.1 replies
V4: XTR1 key ROUTEKEY123, MSMR1 AST-XTR1 and AST-XTR2 yes# for both IIDs, keys untouched
V6: BDR1 show ip bgp vpnv4 vrf CORP 10.60.10.0/23 -> Local, sourced, best; DC-RTR1 holds 10.60.10.0/23 and 10.60.20.0/23 via 10.50.255.1
BDR1 show ip cef vrf CORP 10.60.10.101 -> 10.60.10.0/24 nexthop 10.255.60.11 LISP0.4097
BDR1 show ip cef vrf IOT  10.60.21.102 -> 10.60.21.0/24 nexthop 10.255.60.12 LISP0.4098
BDR1 map-cache 4097: 10.60.10.0/23 via static-send-map-request, Negative cache entry, action: send-map-request (permanent)
                     10.60.10.0/24 via map-reply, complete, locator 10.255.60.11, expires 23:59
DC-RTR1 traceroute 10.60.10.101 source Ethernet0/3: 1 10.50.255.1, 2 10.200.60.3, 3-4 *, 5 10.60.10.101
```
BDR1's RIB is the same before and after (`10.60.10.0/23 static via Null0`); only CEF and the LISP map-cache change. The first ping after a cold map-cache can lose one packet.

F3 evidence from temporary ACLs (counters, not a capture; ACLs removed by node wipe): ACL on DC-RTR1 E0/2 inbound counted PC1's icmp (22 matches): the request reaches the DC. ACL on BDR1 E0/0.3001 outbound counted PC1 icmp (5/5). ACL on BDR1 E0/0.3001 inbound counted the replies 10.50.51.53 to 10.60.10.101 (10 matches): the reply reaches BDR1. ACL on BDR1 E0/3 outbound: 0 matches for UDP 4341 to XTR1 and 0 for UDP 4342 map-requests.

V5 (measured on an earlier version of this lab with the same link, flow and data path of PC1 and PC2 to 10.50.51.53): on SPINE1 e0/3 to BDR1 e0/3 with filter `udp port 4341 or udp port 4342`, CORP is encapsulated to BDR1 on UDP 4341 with LISP flags 0x48 (0x08 on the return), instance-ID 4097, inner 10.60.10.101 to 10.50.51.53; IOT uses instance-ID 4098, inner 10.60.21.102 to 10.50.51.53; every frame is 134 bytes. The same encapsulation was captured in LAB-069 (`../LAB-069/lab069-spine1-bdr1-lisp.pcap`).

## Failure / Recovery Behaviour
Method for the silent failure of the mapping system: `tools/cml-rest.sh link stop` of the link FAB-SPINE1 e0/0 to FAB-MSMR1 e0/0, with both PCs pinging 10.50.51.53 in the background, on the end state (a silent failure: both interfaces stay up/up; one-ended `shutdown` would be a different case). Result: all four registrations went `never no` on MSMR1 after 174 s (3-minute registration lifetime). The background pings showed no `lost` lines (established flows untouched; BDR1 and XTR2 keep their 24 h map-cache entries). A new lookup while the mapping system is gone failed: after `clear ip lisp map-cache instance-id 4097` on XTR1, PC1 to the printer 10.60.11.1 was 3/3 lost and XTR1's map-cache showed `10.60.11.1/32 via data-signal?, incomplete`. After the clear PC1 to DNS also stopped: the clear removes the `10.48.0.0/13` PETR entry too, and even the PETR path needs the mapping system to resolve the new lookup (a new ping left `10.50.51.53/32 incomplete`). Only flows whose map-cache entries were not cleared keep replying (PC2's IOT flow kept going). After `link start` MSMR1 showed both sites `yes#` 3-4 s into the poll and PC1 to the printer replied; 12 s wall time from `link start` to the first reply (one run: "seconds, not minutes").

| Scenario (trigger, end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| Key fix on XTR1 (config applied) until MSMR1 shows AST-XTR1 `yes#` (key re-broken and `clear lisp site *` before runs 2 and 3) | 1 s, 1 s, 1 s | 1-5 s | ETR re-registers on the config change; 1 s poll resolution |
| Both BDR1 map-cache lines re-added (F1, F2 fixed; BDR1 map-cache cleared, loss confirmed) until the first reply from 10.50.51.53 (`ping -c 1 -W 1` polled each 1 s) | PC1 4, 4, 4 s; PC2 4, 4, 4 s (BDR1 cache cleared; without the clear, up to about 60 s after F1 is fixed) | 2-6 s | SSH config session + first map-request/map-reply + 1 s ping timeout and poll |
| Anchor removal on BDR1 until the /23 is gone from FUS1 and DC-RTR1 | at most 2 s (one poll), one run each way | up to 5 s | BGP withdraw on a connected eBGP session; restore also at most 2 s |
| `link stop` SPINE1-MSMR1 until MSMR1 shows all registrations gone (silent failure) | 174 s, 194 s, 187 s, 191 s (wall time incl. 2-5 s overhead) | 170-200 s | 3-minute registration lifetime (LAB-067 measured 180-190 s `(derived)` for the range) |
| F2 fix (PC2's BDR1 map-cache line, F1 fixed) on BDR1 until PC2's first reply from 10.50.51.53 | 52 s (one run) | about 1 min (one run, no range measured) | BGP/VRF import of the /23 plus the map-request; the 4 s row above covers only the BDR1 lines |
| `link start` until MSMR1 shows `yes#` | 3-4 s after the poll started (one run) | seconds | Map-Register retry; one run, no tighter range claimed |

Gotchas: do not wipe DC-DNS1 (after a wipe its link to DC-RTR1 stays dead until `link stop` and `link start`); do not `telnet … 53` from DC-RTR1. After a boot allow 60-90 s before testing; DC-RTR1 learns the /23s about 33 s after FUS1's BGP session settles. After wiping MSMR1 run `clear lisp site *`.

## Answers to Analysis Questions
**Q1** In the mapping system, `show lisp site` on the map server shows missing registrations (and authentication failure counters) and the edges' map-caches show negative entries for prefixes that should exist; the underlay still pings between RLOCs and OSPF is FULL. An underlay or data-plane problem instead shows unreachable RLOCs or encapsulated packets that never arrive. On the border, the discriminator is the capture and the map-request counter: UDP 4341 arrives and nothing is encapsulated back and no map-request is sent (F3), against a map-request answered with a negative reply (F1).

**Q2** Each ticket is a series of two faults: TK1 = F3 + F1, TK2 = F3 + F2. F3 is common to both, so fixing F1 or F2 first (or both) closes nothing, and fixing F3 first closes nothing either because the second cause of each ticket remains. Measured: F3 alone leaves both open, F3+F1 closes TK1 only, F3+F2 closes TK2 only, F1+F2 with F3 open closes neither.

**Q3** A post-window verification pass: from a host in each VN, ping and resolve a shared service; on the map server confirm every site is registered; compare per-VN received prefixes on the border; on the border compare the LISP map-cache and CEF entry for one fabric host with the design pack (the RIB alone looks identical).

**Q4** Catalyst Center Assurance (fabric health and issues: control plane registration/authentication errors, border handoff and routing issues, host onboarding and path trace through the fabric) `(derived; Cisco SD-Access Assurance documentation)`. Nothing on this server produces that view.

**Q5** Besides the RIB: the LISP map-cache (per instance-ID: an ITR consults it for a destination with no covering VN route, and an entry may be positive, negative or "send a map-request") and CEF, the forwarding table built from both. On an edge: VN routing table first; with no covering route, the map-cache decides (positive entry: encapsulate to the RLOC; negative entry or no entry: map-request, and `use-petr` sends non-fabric destinations to the border). On the border: for PC1's request the PETR decapsulates and the VRF routing table (BGP from FUS1) forwards it; for the return traffic the destination 10.60.10.101 has only the Null0 /23 in the RIB, and the LISP map-cache entry `10.60.10.0/23 map-request` makes the proxy-ITR ask the mapping system and encapsulate to the registered RLOC (BDR1 CEF `10.60.10.0/24 nexthop 10.255.60.11 LISP0.4097`). Without that entry the Null0 anchor wins and the packet is discarded.

Debrief: XTR1 could still send because registration is only needed to be found, not to look others up. Only IOT lost the leak because F2 touched IOT's import RT alone; CORP's import was intact. BDR1's RIB is identical in both states because the anchor is the BGP origination (the `network` statement needs it) and the `map-cache <block> map-request` line is the separate instruction "this block is in the overlay": 067 Q1's covering-route rule on the border. In SD-Access the border learns the fabric's endpoint prefixes from the control plane node instead of a hand-written entry `(derived)`. The DC team's "nothing changed on our side that matters" is true: the routes Veridian needs are all there, which tempts the engineer to call the handoff healthy.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), dnsmasq, iol-xe (IOS XE 17.16.1a) |
