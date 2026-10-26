# LAB-024 — Solution

## Summary

Implementation lab: a whole single-homed Internet edge built from requirements. Blueprint: 3.2.c (eBGP: MD5 peering, network + Null0 origination, inbound and outbound prefix filtering) and 3.3.b (PAT to a pool, static NAT for the DMZ); OSPF default origination is a means for R5, not a blueprint objective. The last part (R7) records that a silent failure keeps the session and the static default up, which sets up LAB-026..029.

## Intentional Faults

None (integration lab).

## Diagnosis / Methodology

No faults. Suggested build order, with the check after each step:
1. BGP up: `show ip bgp summary` (state/prefix count) and the `%BGP-5-ADJCHANGE` up line. If Active: MD5 password, neighbour AS and the link address are the three candidates; an MD5 mismatch logs `%TCP-6-BADAUTH` on ISP1.
2. Announce both /26s: `network` needs a matching RIB route, hence the Null0 statics (Q1). Check with ISP1 `show ip bgp neighbors 198.51.100.65 received-routes`.
3. Outbound filter (R2): proved by adding a test route (`ip route 192.0.2.64/26 Null0` + `network`): it enters EDGE1's BGP table but ISP1 still receives two prefixes.
4. NAT roles: e0/0 outside, e0/1 and e0/2 inside; PAT pool, static NAT. Check `show ip nat translations`.
5. Default route and OSPF origination, then the campus default on CORE1.

## Solution Configuration

HQ-EDGE1 (only device changed; tested as one block applied to the start state):

```
ip route 192.0.2.0 255.255.255.192 Null0
ip route 192.0.2.128 255.255.255.192 Null0
ip route 0.0.0.0 0.0.0.0 198.51.100.64
ip prefix-list ISPA-IN seq 5 permit 198.51.100.0/25
ip prefix-list ISPA-IN seq 10 permit 198.51.100.8/29
ip prefix-list VERIDIAN-OUT seq 5 permit 192.0.2.0/26
ip prefix-list VERIDIAN-OUT seq 10 permit 192.0.2.128/26
route-map ISPA-OUT permit 10
 match ip address prefix-list VERIDIAN-OUT
route-map ISPA-IN permit 10
 match ip address prefix-list ISPA-IN
router bgp 65010
 bgp router-id 10.255.10.31
 bgp log-neighbor-changes
 neighbor 198.51.100.64 remote-as 64601
 neighbor 198.51.100.64 password ISPA-64601
 address-family ipv4
  network 192.0.2.0 mask 255.255.255.192
  network 192.0.2.128 mask 255.255.255.192
  neighbor 198.51.100.64 activate
  neighbor 198.51.100.64 route-map ISPA-IN in
  neighbor 198.51.100.64 route-map ISPA-OUT out
router ospf 1
 default-information originate metric 10
ip access-list standard NAT-INSIDE
 permit 10.10.0.0 0.0.255.255
ip nat pool POOL-A 192.0.2.1 192.0.2.1 netmask 255.255.255.192
ip nat inside source list NAT-INSIDE pool POOL-A overload
ip nat inside source static 10.10.60.150 192.0.2.130
interface Ethernet0/0
 ip nat outside
interface Ethernet0/1
 ip nat inside
interface Ethernet0/2
 ip nat inside
```

`default-information originate` has no `always`: the OSPF default exists only while the static default is in the RIB. The solved config is also `environments/EDGE/E0/HQ-EDGE1.cfg`.

## Verification

Captured in CML, trimmed.

- V1: `show ip bgp summary` on EDGE1: `Neighbor 198.51.100.64 V4 AS 64601 ... 00:00:26 2` (2 prefixes received). The BGP table also holds 198.51.100.0/25 and 198.51.100.8/29 (path 64601).
- V2 (R2): `show ip bgp neighbors 198.51.100.65 received-routes` on ISP1: `192.0.2.0/26` and `192.0.2.128/26`, path 65010, Total 2. EDGE1 `advertised-routes`: `*> 192.0.2.0/26 0.0.0.0 ... i`, `*> 192.0.2.128/26`, Total 2.
- V8: after `ip route 192.0.2.64/26 Null0` and `network 192.0.2.64 mask 255.255.255.192`, `clear ip bgp * soft out`: the prefix is in EDGE1's table but not on ISP1 (still two). Removed afterwards.
- V6 (R5): CORE1 `show ip route 0.0.0.0`: `Known via "ospf 1", distance 110, metric 10 ... Tag 1, type extern 2` via 10.10.255.65.
- V4: HQ-PC1 pings 198.51.100.1, 198.51.100.10 and 192.0.2.200: 0% loss. `show ip nat translations`: `icmp 192.0.2.1:1024 10.10.10.101:6 198.51.100.1:6 198.51.100.1:1024`. Static: `--- 192.0.2.130 10.10.60.150`.
- V5 (R4): PROV-SRV1 ping 192.0.2.130 0% loss; `wget http://192.0.2.130/` returns `web-ok`. HQ-SRV1 ping to 198.51.100.1 arrives at ISP1 as `IP: s=192.0.2.130 (Ethernet0/0), d=198.51.100.1`; translation `icmp 192.0.2.130:3 10.10.60.150:3 192.0.2.200:3`.
- V7 (R6): ISP1 `debug ip packet detail` while HQ-PC1 pings 198.51.100.1: only `s=192.0.2.1` seen, no 10.x. (tcpdump on the hosts fails: not root. Transit traffic is CEF-switched and not shown by `debug ip packet`; traffic to ISP1 itself is. A CML packet capture on the EDGE1-ISP1 link also works.)
- MD5 BGP, PAT on a single-address pool and static NAT inbound with the Null0 /26 present all work: `Total active translations: 4 (1 static, 3 dynamic; 3 extended)`. The planned fallback (PAT on the interface address) was not needed.

## Failure / Recovery Behaviour

- **Cable pull** (`shutdown` on both EDGE1 e0/0 and ISP1 e0/0): BGP `Down Interface flap` in the same second (14:41:25); EDGE1 and CORE1 default `% Network not in table`; HQ-PC1 ping 100% loss. Restore (`no shutdown` both ends, 14:42:39-48): static default back at once, CORE1 default back about 9 s after, BGP Up at 14:42:53 (about 14 s), ping 0% loss.
- **Silent failure** (`link stop` EDGE1-ISP1, about 14:44:33): at +75 s ping 100% loss while the BGP session is still Up (`00:02:58`), static default and CORE1 default still present. `%BGP-5-ADJCHANGE ... Down BGP Notification sent` at 14:46:51, about 140 s after the stop (167 s in another run; the 180 s hold timer counts from the last keepalive, so expect about 140-170 s, range 120-180 s). At +190 s the static default is STILL on EDGE1, CORE1 still has the OSPF default, ping 100% loss. `link start`: BGP Up within seconds (14:48:27).
- A one-ended `shutdown` was not tested; stopping a link leaves the IOL interfaces up/up.

## Answers to Analysis Questions

1. Q1: R2 (announce exactly the two assigned /26s) forced them. A BGP `network` statement originates a prefix only if an exact route exists in the RIB; the /26s are not on any interface (users are NATed to them), so each needs an anchor route to Null0. The Null0 statics also keep the prefixes originated whatever happens inside, and the static NAT still works with the Null0 route present because NAT is applied before routing. The outbound filter (R2) is what keeps any other, later route from leaking.
2. Q2: With `always`, EDGE1 would advertise a default into OSPF whether or not it has any Internet route (the static is untracked, and with `always` it would stay even after the static was removed). During a provider outage the campus would keep sending Internet traffic to EDGE1 and have it dropped, instead of losing the default at once. Without `always` the campus loses the default the moment the static goes (and in later labs it can fail over to the other exit): the OSPF default follows the static default's presence (shown in the cable-pull test).
3. Q3: HQ-PC1 (10.10.10.101) sends to its gateway CORE1 (10.10.10.1). CORE1 has only the OSPF E2 default (10.10.255.65) and routes to EDGE1 e0/1 (NAT inside). EDGE1 routes to PROV-SRV1 using the static default 0.0.0.0/0 via 198.51.100.64 out e0/0 (the NAT outside interface), where NAT translates source 10.10.10.101 to 192.0.2.1 (PAT, a port assigned from the single-address pool). ISP1 receives it from 198.51.100.65, routes to 192.0.2.200 (connected on e0/2 via the IX), PROV-SRV1 replies to 192.0.2.1: its gateway is ISP1 (.193), ISP1 learned 192.0.2.0/26 by BGP from 198.51.100.65 and sends it back to EDGE1. EDGE1 reverse-translates the destination 192.0.2.1 to 10.10.10.101 (the translation entry, before routing), then routes to 10.10.10.0/24 via OSPF to CORE1 and on to HQ-PC1.
4. Q4: The link was not detected as down: BGP and the static default only react to interface state or a missed hold timer. The interfaces stayed up/up, BGP waited for the 180 s hold timer (broke after about 140-170 s here) and the untracked static default never goes away, so EDGE1 kept advertising a default into OSPF and the campus black-holed traffic. The Internet reachability must be tested actively: an IP SLA probe with object tracking tied to the static default and to the HSRP priority (LAB-026..029), or BFD for the BGP session.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), unmanaged_switch |
