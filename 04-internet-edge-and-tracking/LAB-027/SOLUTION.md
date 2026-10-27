# LAB-027 — Solution

## Summary

Educational intent: policy-based routing on the LAN gateway: ACL match on the source host, route-map on the ingress interface, `set ip next-hop verify-availability <nh> <seq> track N` so the policy follows a tracked path (SLA 3 / track 3), `set ip next-hop` vs `set ip default next-hop`, local PBR as contrast, and what happens on the HSRP standby gateway. Blueprint: 3.2.d:I (PBR) and 4.4:P (tracking; practised). Foundation lab, no intentional faults.

Build notes: **`set ip default next-hop` and the default route.** You might expect `set ip default next-hop` to be ignored whenever a default route exists. Observed on iol-xe: with only a default route in R1's RIB the default next-hop IS used (PC2 via 10.0.14.4); IOS treats only an explicit (non-default) route as "a route". Therefore requirement R3 uses a temporary specific static route (analogous to a provider prefix learned by BGP) to show the difference. The lab runs 9 licensed nodes (the two unmanaged switches count). `debug ip policy` was not tested.

## Intentional Faults

None (foundation lab). Starting state: LAB-026's SLA 1/track 1/HSRP design on R1 only (SLA 2–4 removed; SLA 3/track 3 here is a new R4-path probe, not 026's RTT track) (HSRP active 110, `standby 10 track 1 decrement 20`, tracked default via R3 distance 1, floating default via R4 distance 5, SLA 1/track 1, SLA 3/track 3 reachability `delay up 20` on the pinned 10.0.100.4/32 via R4 with Null0 AD 250 backup), no policy.

## Diagnosis / Methodology

Not applicable. Working method: (1) read the starting state (`show track brief`, `show ip route 0.0.0.0`, traceroute from both PCs), (2) ACL + route-map + `ip policy` on e0/2, (3) check `show ip policy`, `show route-map` counters and the traceroutes, (4) test each failure and read track 3 and the traces.

## Solution Configuration

R1 (as tested):

```
ip access-list extended PC2-HOST
 permit ip host 10.0.10.102 any
route-map PBR-PC2 permit 10
 match ip address PC2-HOST
 set ip next-hop verify-availability 10.0.14.4 1 track 3
interface Ethernet0/2
 ip policy route-map PBR-PC2
```

R3 demonstration (temporary): `ip route 10.0.100.0 255.255.255.0 10.0.13.3`, then change the set line to `set ip next-hop 10.0.14.4` and to `set ip default next-hop 10.0.14.4`; remove the route afterwards. R4 demonstration (temporary): `ip access-list extended` permitting host 10.0.10.2, `route-map PBR-LOCAL permit 10` with `set ip next-hop 10.0.14.4`, `ip local policy route-map PBR-LOCAL`; test `traceroute 10.0.100.200 source Ethernet0/2`; then `no ip local policy route-map PBR-LOCAL`. No change on R2, R3, R4.

## Verification

- `show ip policy` -> `Ethernet0/2 PBR-PC2`; `show route-map` shows `ip next-hop verify-availability 10.0.14.4 1 track 3  [up]` and "Policy routing matches: 14 packets, 1030 bytes"; ACL `10 permit ip host 10.0.10.102 any (14 matches)`.
- PC1 `traceroute -n 10.0.100.200`: `1 10.0.10.2 / 2 10.0.13.3 / 3 10.0.100.200`. PC2: `1 10.0.10.2 / 2 10.0.14.4 / 3 10.0.100.200` (ping 5/5). Return traffic from SRV1 (gateway R3) is not policy-routed: asymmetric, works without NAT.
- Start state (fresh import): track 1 and 3 Up, default via 10.0.13.3, R1 HSRP Active 110, empty `show ip policy`/`show route-map`, PC1 and PC2 both via 10.0.13.3.
- R3 with the explicit route on R1: `set ip next-hop 10.0.14.4` -> PC2 via 10.0.14.4; `set ip default next-hop 10.0.14.4` -> PC2 via 10.0.13.3 (policy bypassed). With only the default route present, both forms -> PC2 via 10.0.14.4 (plain form matched 23 -> 32 packets).

## Failure / Recovery Behaviour

- **Silent failure R1 e0/1 – R4 e0/0** (with verify-availability): PC2 `ping -c 100 -W 1` lost 4 (~4 s); track 3 Down within seconds (no down delay), PC2 traceroute then via 10.0.13.3. After link start, track 3 Up 12–20 s later (`delay up 20`), PC2 back via 10.0.14.4 (checked at 20 s and 40 s).
- **Without verify-availability** (plain `set ip next-hop`): `ping -c 40`, link stopped about 15 s before the end: 25/40 received, 37% loss = every ping after the stop (black hole); track 3 Down but ignored.
- **Local policy:** R1's own `traceroute 10.0.100.200` uses 10.0.13.3 (probes and pings are not policy-routed; SLA 3 and track 3 unaffected). With local policy `PBR-LOCAL` (ACL host 10.0.10.2, `set ip next-hop 10.0.14.4`), `traceroute ... source Ethernet0/2` goes via 10.0.14.4 (2 matches); without `source` it stays via R3 (the source is then the egress address 10.0.13.1). `source Loopback0` fails (providers have no route to 10.255.0.1). `show ip local policy` -> "Local policy routing is enabled, using route map PBR-LOCAL"; after removal "disabled".
- **HSRP failover** (cable pull R1 e0/0 and R3 e0/0, both `shutdown`): track 1 Down, R1 priority 90 Standby, R2 Active (preempt). PC1 and PC2 both `10.0.10.3 -> 10.0.24.4 -> 10.0.100.200`; R1's policy counter frozen at 217.
- Restore: R1, R3, PC2 wiped and restarted; start-state checks matched, and so did a fresh import of the YAML.

## Answers to Analysis Questions

Q1. The policy is applied to packets entering an interface (`ip policy` on e0/2), so PC2's forwarded traffic is policy-routed. Packets R1 itself originates (pings, SLA probes, traceroute) do not enter through an interface, so only `ip local policy` affects them; observed: R1's traceroute stayed on R3, and with a local policy it moved only when sourced from Ethernet0/2 (the ACL matched 10.0.10.2).
Q2. Without `verify-availability` the router keeps forwarding to 10.0.14.4 even though track 3 is Down: black hole. Observed: 25 of 40 pings received, every ping after the link stop lost (37%), while track 3 showed Down. With it the next hop is ignored when the track is Down, PC2 follows the routing table within seconds (4 lost pings) and returns after the track's `delay up 20`.
Q3. Examples: send voice or bulk traffic by source or protocol to a specific provider or WAN link, steer to a firewall or scrubbing service, push traffic into a tunnel (WAN module). The E2 edge needs destination-based failover for all users and a symmetrical, simple state: a tracked default route changes the routing table itself (visible to HSRP, redistribution and the standby router), while PBR is per-interface, per-router, hides paths from `show ip route`, and is not applied on the other gateway.
Q4. Traffic arriving at a gateway without the policy is routed normally. After the failover R2 is active; it has no policy, so both PCs follow R2's table (default via R4, 10.0.24.4), and PC1 and PC2 look the same. The path via R4 there is R2's routing, not the policy (R1's counter stopped).
Q5. `set ip next-hop` is applied first and the routing table is not consulted for that decision; `set ip default next-hop` is applied only when the routing table has no explicit route for the destination. Observed: with a specific static route for 10.0.100.0/24 via R3, the default form was bypassed (PC2 via R3), but with only a default route in the table it was used (PC2 via R4), because IOS does not count the default route as a match for this test. R1 needs `set ip next-hop` (with `verify-availability`), so the policy applies whatever the routing table holds.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-25 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), unmanaged_switch |
