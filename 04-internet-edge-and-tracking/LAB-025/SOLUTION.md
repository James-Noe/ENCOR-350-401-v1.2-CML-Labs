# LAB-025 — Solution

## Summary

An implementation lab: HQ-EDGE2 joins ISP-B under one policy with HQ-EDGE1 and ISP-A, and IPv6 goes live on both edges. The student authors, per provider: an announcement filter (route-map with prefix-lists), AS-path prepending (two prepends on the DMZ /26 and the /48 towards ISP-B), a no-transit outbound filter in IPv4 and IPv6 (iBGP-learned routes are advertised to eBGP peers, so each edge would otherwise pass ISP-A's routes to ISP-B and the reverse), local preference 200 for the supplier network 198.51.100.8/29 on EDGE2, local preference 150 on EDGE1 for ISP-A's IPv6 default, IPv6 eBGP and iBGP (separate IPv6 neighbours, `no neighbor ... activate` in the IPv4 address family), and an OSPFv3 default originated from BGP. Blueprint: 3.2.c:P (BGP), SK-RM:R (route-maps, prefix-lists), IPv6:R (routing). Not a troubleshooting lab.

## Intentional Faults

None (integration lab). The start state is deliberately incomplete: no EDGE2-ISP-B session, no IPv6 BGP, no policy, no OSPFv3 default origination, no EDGE2 default.

## Diagnosis / Methodology

1. Build the sessions first (R1) and read the providers' looking glass. With only the sessions up and no policy, `show ip bgp neighbors 203.0.113.65 received-routes` on PROV-ISP2 lists 192.0.2.0/26 (user block A: Veridian's own, but meant for ISP-A), 192.0.2.64/26, 192.0.2.128/26 (path 65010), 198.51.100.0/25 and 198.51.100.8/29 (path 65010 64601). The last two are ISP-A's routes that Veridian would carry to ISP-B: the transit leak. The leaked set depends on order: at least 198.51.100.0/25; the /29 too if ISPB-IN is not yet applied (once it is, EDGE2's own eBGP path for the /29 is best and is not re-advertised). ISP-B's inbound filter drops them, so only soft reconfiguration (`received-routes`) shows it. HQ-EDGE1 does not leak IPv4 because its outbound filter (ISPA-OUT from the E0 stage) already limits it; in IPv6 neither edge has a filter until the student writes one.
2. Announcements (R2): a prefix-list per provider and an outbound route-map. ISP-B's best path to the DMZ block with no prepend is direct (65010). With one prepend the path lengths tie (2 = 2, 64601 65010 versus 65010 65010) and ISP-B picked ISP-A only on a later tie-break, which is no guarantee; two prepends make it deterministic.
3. Outbound exit (R4): EDGE1's default is static (AD 1) and ISP-A's routes arrive with local preference 100; EDGE2's inbound route-map sets local preference 200 on 198.51.100.8/29 only. Across iBGP EDGE1 sees that route with LP 200 against its own eBGP LP 100, so BGP selects the iBGP route although eBGP has the lower AD (AD is compared only after BGP has chosen). Weight would stay local to EDGE2 and invisible to EDGE1.
4. IPv6 default (R5): ISP-A's ::/0 is accepted on EDGE1 with local preference 150, so both edges prefer it; EDGE2's BGP ::/0 shows `r` (RIB-failure) because OSPFv3 E2 from EDGE1 (AD 110) beats iBGP (AD 200). EDGE2's own OSPFv3 origination (metric 30) is dormant until EDGE1 loses its ::/0.
5. Build note (RA preference): HQ-EDGE1's DMZ interface carries `ipv6 nd router-preference High` (EDGE2 uses the default, Medium), so HQ-SRV1's IPv6 default router is EDGE1 whenever it is up. This is part of the day-0 start state, not a requirement; it is why the DMZ IPv6 gateway does not follow HSRP or tracking in later labs.

## Solution Configuration

**HQ-EDGE2** (config mode)

```
ip route 192.0.2.64 255.255.255.192 Null0
ip route 192.0.2.128 255.255.255.192 Null0
router bgp 65010
 neighbor 203.0.113.64 remote-as 64602
 neighbor 203.0.113.64 password ISPB-64602
 address-family ipv4
  network 192.0.2.64 mask 255.255.255.192
  network 192.0.2.128 mask 255.255.255.192
  neighbor 203.0.113.64 activate
ip prefix-list POOL-B-OUT seq 5 permit 192.0.2.64/26
ip prefix-list DMZ-OUT seq 5 permit 192.0.2.128/26
ip prefix-list ISPB-IN seq 5 permit 203.0.113.0/25
ip prefix-list ISPB-IN seq 10 permit 203.0.113.8/29
ip prefix-list ISPB-IN seq 15 permit 198.51.100.8/29
ip prefix-list SUPPLIER-A seq 5 permit 198.51.100.8/29
route-map ISPB-OUT permit 10
 match ip address prefix-list DMZ-OUT
 set as-path prepend 65010 65010
route-map ISPB-OUT permit 20
 match ip address prefix-list POOL-B-OUT
route-map ISPB-IN permit 10
 match ip address prefix-list SUPPLIER-A
 set local-preference 200
route-map ISPB-IN permit 20
 match ip address prefix-list ISPB-IN
router bgp 65010
 address-family ipv4
  neighbor 203.0.113.64 route-map ISPB-IN in
  neighbor 203.0.113.64 route-map ISPB-OUT out
ip route 0.0.0.0 0.0.0.0 203.0.113.64
router ospf 1
 default-information originate metric 30
ipv6 route 2001:db8:10::/48 Null0
ipv6 prefix-list V6-OUT seq 5 permit 2001:db8:10::/48
route-map ISPB-OUT-V6 permit 10
 match ipv6 address prefix-list V6-OUT
 set as-path prepend 65010 65010
router bgp 65010
 neighbor 2001:db8:f002:ffff::64 remote-as 64602
 neighbor 2001:db8:f002:ffff::64 password ISPB-64602
 neighbor 2001:db8:ffff:10::31 remote-as 65010
 neighbor 2001:db8:ffff:10::31 update-source Loopback0
 address-family ipv4
  no neighbor 2001:db8:f002:ffff::64 activate
  no neighbor 2001:db8:ffff:10::31 activate
 address-family ipv6
  network 2001:db8:10::/48
  neighbor 2001:db8:f002:ffff::64 activate
  neighbor 2001:db8:f002:ffff::64 route-map ISPB-OUT-V6 out
  neighbor 2001:db8:ffff:10::31 activate
  neighbor 2001:db8:ffff:10::31 next-hop-self
router ospfv3 1
 address-family ipv6 unicast
  default-information originate metric 30
```

**HQ-EDGE1** (config mode)

```
ipv6 route 2001:db8:10::/48 Null0
ipv6 prefix-list V6-OUT seq 5 permit 2001:db8:10::/48
route-map ISPA-OUT-V6 permit 10
 match ipv6 address prefix-list V6-OUT
route-map ISPA-IN-V6 permit 10
 set local-preference 150
router bgp 65010
 neighbor 2001:db8:f001:ffff::64 remote-as 64601
 neighbor 2001:db8:f001:ffff::64 password ISPA-64601
 neighbor 2001:db8:ffff:10::32 remote-as 65010
 neighbor 2001:db8:ffff:10::32 update-source Loopback0
 address-family ipv4
  no neighbor 2001:db8:f001:ffff::64 activate
  no neighbor 2001:db8:ffff:10::32 activate
 address-family ipv6
  network 2001:db8:10::/48
  neighbor 2001:db8:f001:ffff::64 activate
  neighbor 2001:db8:f001:ffff::64 route-map ISPA-IN-V6 in
  neighbor 2001:db8:f001:ffff::64 route-map ISPA-OUT-V6 out
  neighbor 2001:db8:ffff:10::32 activate
  neighbor 2001:db8:ffff:10::32 next-hop-self
router ospfv3 1
 address-family ipv6 unicast
  default-information originate metric 10
```

Optional IPv6 inbound filter (measured): the configuration above filters IPv6 outbound only (V6-OUT) and has no IPv6 inbound prefix-list, unlike IPv4. The providers announce only ::/0 and their own /48, so the omission changes nothing here, but a production edge filters inbound per provider and matches the prefix-list before the `set local-preference`. Proven on the live lab, applied on top of the configuration above:

```
HQ-EDGE1:
ipv6 prefix-list V6-ISPA-IN seq 5 permit ::/0
ipv6 prefix-list V6-ISPA-IN seq 10 permit 2001:db8:f001::/48
route-map ISPA-IN-V6 permit 10
 match ipv6 address prefix-list V6-ISPA-IN
 (set local-preference 150 kept)
HQ-EDGE2:
ipv6 prefix-list V6-ISPB-IN seq 5 permit ::/0
ipv6 prefix-list V6-ISPB-IN seq 10 permit 2001:db8:f002::/48
route-map ISPB-IN-V6 permit 10
 match ipv6 address prefix-list V6-ISPB-IN
router bgp 65010
 address-family ipv6
  neighbor 2001:db8:f002:ffff::64 route-map ISPB-IN-V6 in
```

Apply it with the per-neighbour refresh, `clear bgp ipv6 unicast 2001:db8:f001:ffff::64 soft in` on EDGE1 and `clear bgp ipv6 unicast 2001:db8:f002:ffff::64 soft in` on EDGE2. In the re-check `clear bgp ipv6 unicast * soft in` did not apply the new filter, the per-neighbour form did. With bogus 2001:DB8:BAD1::/48 and BAD2 injected at the providers, both were installed before and gone from both edges after, the real ::/0 and /48 routes were kept (PfxRcd 3 to 2 per eBGP peer) and no session reset.

After the configuration run `clear ip bgp * soft` on both edges (re-applies the route-maps without resetting sessions). The IPv6 refresh is separate: use the per-neighbour `clear bgp ipv6 unicast <neighbor> soft in` (and `soft out`) for the IPv6 neighbours. IPv6 convergence after BGP changes takes about 1-2 minutes on the first pass.

Tested in three stages (A: EDGE2 IPv4 eBGP only, to capture the leak; B: IPv4 policy; C: IPv6) and then as the merged script above, run clean on the start state of the re-imported lab.

## Verification

Captured on a fresh import after applying the merged solution.

Sessions on both edges (IPv4 summary, IPv6 summary), the supplier route and the IPv6 default on EDGE1:

```
show ip bgp summary | include ^Neighbor|^198|^10.255
Neighbor        V           AS MsgRcvd MsgSent   TblVer  InQ OutQ Up/Down  State/PfxRcd
10.255.10.32    4        65010      25      22        9    0    0 00:07:57        5
198.51.100.64   4        64601      14      15        9    0    0 00:07:23        2
show bgp ipv6 unicast summary | begin Neighbor
Neighbor        V           AS MsgRcvd MsgSent   TblVer  InQ OutQ Up/Down  State/PfxRcd
2001:DB8:F001:FFFF::64
                4        64601       9       7        5    0    0 00:03:28        2
2001:DB8:FFFF:10::32
                4        65010       8       9        5    0    0 00:03:30        2
```

```
show ip bgp 198.51.100.8/29 | include from|localpref
    10.255.10.32 (metric 11) from 10.255.10.32 (10.255.10.32)
      Origin IGP, metric 0, localpref 200, valid, internal, best
    198.51.100.64 from 198.51.100.64 (198.51.100.1)
      Origin IGP, metric 0, localpref 100, valid, external
show ip route 198.51.100.8 | include Known|via
  Known via "bgp 65010", distance 200, metric 0
show ipv6 route ::/0 | include Route|via|Known|%
  Known via "bgp 65010", distance 20, metric 0
  Route count is 1/1, share count 0
      Route metric is 0, traffic share count is 1
```

What ISP-B receives after the filters (two IPv4 blocks, the DMZ /26 prepended twice; the /48 shown as received on the IPv6 neighbour):

```
show ip bgp neighbors 203.0.113.65 received-routes | begin Network
     Network          Next Hop            Metric LocPrf Weight Path
 *>   192.0.2.64/26    203.0.113.65             0             0 65010 i
 *    192.0.2.128/26   203.0.113.65             0             0 65010 65010 65010 i

Total number of prefixes 2
show bgp ipv6 unicast neighbors 2001:db8:f002:ffff::65 received-routes | include /
 *    2001:DB8:10::/48 2001:DB8:F002:FFFF::65
```

Before the filter (stage A, captured): ISP-B received 192.0.2.0/26, 192.0.2.64/26, 192.0.2.128/26 (path 65010), 198.51.100.0/25 and 198.51.100.8/29 (path 65010 64601; the /29 only while ISPB-IN is not yet applied). After stage B: only 192.0.2.64/26 (65010) and 192.0.2.128/26 (65010 65010 65010). ISP-A receives only 192.0.2.0/26 and 192.0.2.128/26 (and the IPv6 /48).

Inbound preference seen from PROV-ISP2 (best path through AS 64601 in both families) and the traceroute across ISP-A:

```
show ip bgp 192.0.2.128/26 | include 65010|best
  65010 65010 65010, (received & used)
  64601 65010
      Origin IGP, localpref 100, valid, external, best
show bgp ipv6 unicast 2001:db8:10::/48 | include 65010|best
  65010 65010 65010, (received & used)
  64601 65010
      Origin IGP, localpref 100, valid, external, best
traceroute 192.0.2.130 source Loopback0
  1 198.51.100.66 [AS 64601]   2 198.51.100.65 [AS 64601]   3 192.0.2.130 [AS 65010]
traceroute 2001:db8:10:60::150 source Loopback0
  1 2001:DB8:F001:FFFF::66   2 2001:DB8:F001:FFFF::65   3 2001:DB8:10:60::150
```

Outbound traceroutes from HQ-PC1 (R4): PROV-SRV1 via ISP-A; 203.0.113.10 and 198.51.100.10 via EDGE2 and ISP-B:

```
traceroute -n 192.0.2.200       10.10.10.1  10.10.255.65  198.51.100.64  192.0.2.200
traceroute -n 203.0.113.10      10.10.10.1  10.10.255.65  10.10.255.69  203.0.113.64
traceroute -n 198.51.100.10     10.10.10.1  10.10.255.65  10.10.255.69  203.0.113.64  198.51.100.66
traceroute -6 -n 2001:db8:f001:200::200   2001:db8:10:10::1  2001:db8:10:ffff::65  2001:db8:f001:ffff::64  2001:db8:f001:200::200
```

IPv6 default in steady state: HQ-EDGE1 `::/0` via BGP (distance 20, LP 150); HQ-EDGE2 and HQ-CORE1 `::/0` via OSPF (E2, metric 10, from EDGE1); `show ospfv3 database external` on EDGE2 lists only EDGE1's origination (metric 10): EDGE2's own (metric 30) is dormant. HQ-PC1 pings 2001:db8:f001:200::200 with 0% loss. HQ-CORE1 IPv4 default: OSPF metric 10 via 10.10.255.65.

## Failure / Recovery Behaviour

Cable pull (`shutdown` on both ends of EDGE1 e0/0 and ISP1 e0/0). Everything had converged at the first check, about 1 minute after the shutdown (the CLI is too slow to time it better: record "within about 1 min"):
- IPv4: EDGE1's static default is removed along with the BGP session and the campus default becomes OSPF metric 30 via EDGE2. PC1 reaches PROV-SRV1 through 10.10.255.67, 203.0.113.64.
- IPv6: ::/0 is withdrawn at once; EDGE2's own BGP ::/0 and its OSPFv3 origination (metric 30) take over (core v6 default metric 30); PC1 reaches PROV-SRV1 via 2001:db8:10:ffff::67 and ISP-B.
- Inbound: ISP-B's best path for the DMZ block and the /48 becomes the direct 65010 65010 65010, the only path. ISP-A reaches Veridian through 64602 65010 65010 65010 over the interconnect.
- Recovery (no shutdown on both ends): core default back to metric 10 via EDGE1; BGP IPv4 and IPv6 Up in 1-2 min (about 55 s and about 2 min in two runs); ISP-B's best DMZ path returns to 64601 65010.

Silent failure (`link stop`): at +70 s both sessions were still Up and PC1 lost 100% of IPv4 and IPv6 traffic to PROV-SRV1. The hold timer expired about 170 s after the stop (`BGP Notification sent`): the IPv6 ::/0 was withdrawn, the core followed EDGE2 (metric 30) and IPv6 pings recovered. IPv4 never recovered: the static default stayed (`Known via "static"`) and PC1 to 192.0.2.200 was still 100% loss at +4 min. Link start: sessions Up about 55 s later and pings OK. This gap is what LAB-026 to 029 close.

## Answers to Analysis Questions

Q1: PROV-SRV1 (default case, ISP-A): on EDGE1 the static default (AD 1) and the BGP routes from ISP-A at LP 100; EDGE2 has its own default (static to ISP-B) but the OSPF default from EDGE1 (metric 10 against the 30 it originates) is what the campus uses, so traffic goes to EDGE1. ISP-B networks (203.0.113.10): EDGE1 learns 203.0.113.8/29 over iBGP from EDGE2 (next hop EDGE2), and that more specific route beats the static default on EDGE1; on EDGE2 the eBGP route from ISP-B is the only one. Longest prefix match decides, not an attribute. Supplier 198.51.100.8/29: local preference 200 on EDGE2's inbound route-map; EDGE1 sees LP 200 (iBGP) against LP 100 (eBGP) and selects the iBGP route, then EDGE2 sends it out to ISP-B. IPv6 default: LP 150 on EDGE1's eBGP ::/0; on EDGE2 the BGP ::/0 loses at the RIB on AD (OSPFv3 110 against iBGP 200).
Q2: Local preference (200 on EDGE2 for the supplier network, carried to EDGE1 over iBGP). Weight is local to the router that sets it and is not carried in BGP updates, so EDGE1 would never see EDGE2's preference and would choose its own eBGP route. Local preference travels over iBGP to every router in the AS.
Q3: AS-path prepending towards ISP-B, twice (DMZ block and /48). With one prepend, ISP-B compared two paths of length 2 (direct 65010 65010 against 64601 65010) and chose ISP-A only on a later tie-break. Prepending only influences path length, which is compared after local preference: any AS that sets a higher local preference on the path through ISP-B, or filters or strips prepends, ignores it.
Q4: Before: received-routes on ISP-B listed four or five prefixes (path 65010 64601): always ISP-A's 198.51.100.0/25, and 198.51.100.8/29 only while ISPB-IN is not yet applied on EDGE2, so the leaked set depends on order. ISP-B's inbound filter accepted only 192.0.2.0/24 /24-/26, so the leaked prefixes were received but not accepted: the best-path table hides them, which is why `received-routes` (soft reconfiguration) is the evidence. After: received-routes shows only 192.0.2.64/26 and the prepended 192.0.2.128/26.
Q5: IPv4: the interface down removed the static default (and the BGP session), so the OSPF default originated by EDGE1 disappeared and the campus followed EDGE2's metric-30 default. IPv6: the BGP session drop withdrew ::/0, and EDGE2's OSPFv3 origination took over. On a silent failure the interface stays up: the IPv6 default recovers only when the BGP hold timer expires (about 170 s), the IPv4 static default never recovers because nothing tracks reachability.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), unmanaged_switch |
