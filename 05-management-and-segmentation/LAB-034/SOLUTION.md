# LAB-034 — Solution

## Summary
Educational intent: write one traffic policy in both stacks, place it deliberately, and prove it with counters. It teaches extended and named ACLs, sequence-number editing, `log` evidence, the IPv6 implicit neighbour-discovery permits that an explicit `deny ipv6 any any` removes, why a filter on a routed interface must not catch the routing protocol, and `access-class` / `ipv6 access-class` on the VTYs. Blueprint: 5.2.a (ACLs, implementation level), IPv6:R (IPv6 ACLs, reinforcement). Builds on LAB-019 (dual stack, OSPFv3) and LAB-032 (VTY consistency). Type I: there are no intentional faults.

Design decisions:
- Hosts have static IPv4 and IPv6 addresses and a static IPv6 default route via the router's `::1`; the routers suppress RAs on the LAN ports (`ipv6 nd ra suppress all`), so no SLAAC addresses appear.
- OSPFv2 and OSPFv3 run on every interface (LAN ports and loopbacks passive; e0/0 point-to-point). This gives full reachability and one adjacency on e0/0.
- Day-0 VTY: `login local`, `transport input ssh`, `line vty 0 4`, RSA key, `ip ssh version 2`, enable secret. Router e0/3 is shut down.

## Intentional Faults
None (implementation lab).

## Diagnosis / Methodology
Evidence path for the policy tests, from a host, with the router counters as the proof:
1. Read `show access-lists` before and after each test (no `clear` needed).
2. Permitted test (`wget http://10.0.50.50/`, `ping`): the permit entry's match counter rises by the packets sent.
3. Denied test (`nc -w3 10.0.50.50 22`, `wget ...:8080`): the `deny ... log` entry shows a `%SEC-6-IPACCESSLOGP` / `%IPV6_ACL-6-ACCESSLOGP` line naming your host's source address and the port you tried, and its counter rises. Guest LAN DHCP discovers (`udp 0.0.0.0(68) -> 255.255.255.255(67)`) and IPv6 router solicitations also land in the deny counters: tell them apart by source address and port.
4. Client messages tell where a refusal happened. An interface ACL drop gives `Host is unreachable` (IPv4, the router sends ICMP admin-prohibited) or `Permission denied` (IPv6 with busybox wget). A VTY `access-class` drop answers the SYN with a RST: `Connection refused` for ssh, with no handshake (measured also in LAB-037 and LAB-038 F1). A permitted but closed port (TCP 443 before a listener exists) gives the same `Connection refused`, so the client message cannot tell a VTY-ACL refusal from a closed port: use the access-list counter or the `log` line. ICMP-unreachable (interface ACL) vs RST (VTY ACL or closed port) tells an interface ACL from the rest.
5. Why plausible-but-wrong causes fail: a standard ACL cannot match ports or destination; an IPv6 ACL with the explicit final deny and no ND lines looks correct for some seconds and then fails, within about a minute (below); an ACL applied to e0/0 without OSPF permits drops the adjacency after the dead timer (below).

## Solution Configuration
Tested config (applied in one pass).

R1:
```
ip access-list extended USERS-IN
 permit tcp 10.0.10.0 0.0.0.255 10.0.50.0 0.0.0.255 eq 80
 permit icmp 10.0.10.0 0.0.0.255 10.0.50.0 0.0.0.255 echo
 deny ip 10.0.10.0 0.0.0.255 10.0.50.0 0.0.0.255 log
 permit ip any any
ipv6 access-list USERS6-IN
 permit tcp 2001:DB8:0:10::/64 2001:DB8:0:50::/64 eq 80
 permit icmp 2001:DB8:0:10::/64 2001:DB8:0:50::/64 echo-request
 deny ipv6 2001:DB8:0:10::/64 2001:DB8:0:50::/64 log
 permit ipv6 any any
ip access-list extended GUEST-IN
 permit ip 10.0.30.0 0.0.0.255 host 198.51.100.1
 deny ip any any log
ipv6 access-list GUEST6-IN
 permit ipv6 2001:DB8:0:30::/64 host 2001:DB8:F001::1
 permit icmp any any nd-ns
 permit icmp any any nd-na
 deny ipv6 any any log
interface Ethernet0/1
 ip access-group USERS-IN in
 ipv6 traffic-filter USERS6-IN in
interface Ethernet0/2
 ip access-group GUEST-IN in
 ipv6 traffic-filter GUEST6-IN in
```
R1 and R2 (management):
```
ip access-list standard MGMT-ONLY
 permit 10.0.99.0 0.0.0.255
ipv6 access-list MGMT6-ONLY
 permit ipv6 2001:DB8:0:99::/64 any
line vty 0 4
 access-class MGMT-ONLY in
 ipv6 access-class MGMT6-ONLY in
```
R5 change (R1, live ACL, one inserted line):
```
ip access-list extended USERS-IN
 15 permit tcp 10.0.10.0 0.0.0.255 host 10.0.50.50 eq 443
```
IPv6 equivalent: `ipv6 access-list USERS6-IN` then `sequence 15 permit tcp 2001:DB8:0:10::/64 host 2001:DB8:0:50::50 eq 443` (IPv6 ACLs need the `sequence` keyword to insert).

Placement (R6): USERS-IN / USERS6-IN on R1 e0/1 inbound and GUEST-IN / GUEST6-IN on R1 e0/2 inbound, because extended ACLs go as close to the source as possible and drop unwanted traffic before it crosses the R1-R2 link; they are inbound so they do not touch router-originated traffic. The VTY ACLs are standard (source only) on every VTY line of both routers. The GUEST6-IN ND permits come before the final deny. Alternative accepted: guests filtered on R2 (see Q5).

## Verification
Captured on CML 2.10.0, trimmed.
- Users, permitted: PC1 ping and `wget` to SRV1 OK in IPv4 and IPv6; USERS-IN seq 10 5 matches, seq 20 4 matches.
- Users, denied: `nc -w3 10.0.50.50 22` rc=1, log `list USERS-IN denied tcp 10.0.10.10(40723) -> 10.0.50.50(22)`; IPv6 `%IPV6_ACL-6-ACCESSLOGP: list USERS6-IN/30 denied tcp 2001:DB8:0:10::10(57102) -> 2001:DB8:0:50::50(8080)`.
- Guests: PC3 ping 198.51.100.1 and 2001:db8:f001::1 OK; PC3 to SRV1, 10.0.30.1, 10.255.0.2, PC1, 2001:db8:0:50::50, 2001:db8:0:30::1 and 2001:db8:0:12::2 all 100% loss. GUEST-IN seq 10 2 matches, `deny ip any any log (22 matches)`. GUEST6-IN ND permits matched 2 each, and a denied router solicitation (133) to FF02::2 showed in the deny line.
- Management: PC2 SSH (admin) to 10.0.12.0, 2001:db8:0:12::1, 10.0.99.1, 2001:db8:0:99::1 succeeded: `%SEC_LOGIN-5-LOGIN_SUCCESS ... Source: 10.0.99.99` and `Source: 2001:DB8:0:99::99`. PC1 ssh to 10.0.10.1 and 2001:db8:0:10::1: `Connection refused` (rc=255); to 10.0.50.1: `Host is unreachable`. PC3 ssh to 10.0.30.1: `Host is unreachable`. OSPFv2 and OSPFv3 FULL throughout.
- R5: before the insert, `wget` to 10.0.50.50:443 = `Host is unreachable`. After `15 permit tcp ... host 10.0.50.50 eq 443` (no removal) = `Connection refused` (reaches SRV1, no listener), seq 15 1 match.
- R4, fixed policy: with `permit icmp any any nd-ns sequence 35` and `nd-na sequence 36` placed before the final deny, 60 of 60 pings ok over 3 minutes (several cache aging cycles), nd-ns 12 and nd-na 12 matches.
- Start state on a fresh import of the YAML: OSPFv2/v3 FULL, no ACLs, every ping 0% loss, both wgets `web-ok`.

## Failure / Recovery Behaviour
Method: interface ACL experiments only. No link or node was stopped or shut down.
- **IPv6 deny without ND permits.** `USERS6-IN` with an explicit final `deny ipv6 any any log` and no ND lines, applied at 22:16:08, PC1 `ping -6` SRV1 every ~3 s: permitted traffic worked until iteration 21 and failed from iteration 22 (about 55 s after apply in this run) to the end of a 75-iteration run. Four more runs measured 11 to 37 s; by the ND timers (reachable time randomised 15-45 s, then DELAY/PROBE) the break comes within about a minute (derived). R1's neighbour entry for the next hop went STALE, and the deny line counted 118 matches. Cause: an explicit `deny ipv6 any any` overrides the implicit `permit icmp any any nd-ns/nd-na` that sit at the end of every IPv6 ACL, so neighbour refresh fails once the cache ages. Recovery: add the two ND permits before the deny. Tell students to wait 3 minutes, not 1.
- **OSPF dropped by an interface ACL.** IPv4 ACL on R1 e0/0 inbound permitting only TCP/22 from the admin LAN: `%SEC-6-IPACCESSLOGRP: list E00-IN denied ospf 10.0.12.1 -> 224.0.0.5`, then `OSPF-5-ADJCHG ... FULL to DOWN, Neighbor Down: Dead timer expired` about 31 s after the apply (teaching range 25 to 40 s; the point-to-point dead timer is 40 s from the last hello). IPv6 `ipv6 traffic-filter` equivalent: `list E00V6-IN/20 denied 89 FE80::... -> FF02::5`, then `OSPFv3-5-ADJCHG ... FULL to DOWN`; ND (types 135/136) was denied too. Removing the ACL brought both adjacencies back to FULL.

## Answers to Analysis Questions
Q1. An explicit `deny ipv6 any any` (log or not) placed last removes the implicit `permit icmp any any nd-ns` and `nd-na` that every IPv6 ACL ends with. Cached neighbours keep working until aging, then ND for the next hop is dropped and forwarding fails (within about a minute; 11-37 s measured in 4 runs). Fix: permit `nd-ns` and `nd-na` before the deny (and permit OSPFv3 or other link-local control traffic on routed interfaces).
Q2. A standard ACL matches only the source address, so it cannot allow web and ping while refusing the rest: it would have to permit or deny all user traffic. To keep users out of the server LAN it must sit as close to the destination as possible (R2 e0/1 outbound), and there it blocks everything users send to the servers, including the permitted web and ping (placed at the source it would also block users' access to everything else). IPv6 has no standard ACLs; its ACLs are all the extended form.
Q3. Read the counters and log line before and after the single test: the matching entry's count rises by the packet count you sent, and the log line shows your host's source address and the destination port you chose. Other traffic is excluded by source address and port: guest DHCP broadcasts and IPv6 router solicitations also hit the guest deny lines. Use `log` with the test source, or compare counters with nothing else running.
Q4. An `access-class` filters only sessions to the router's own VTY lines. It does not filter transit traffic, other services (a different management protocol on another port), or traffic to other addresses; an interface ACL filters everything crossing the port. Client behaviour differs: an interface ACL drop gives `Host is unreachable` (ICMP admin-prohibited, or silence), while the access-class refuses the SYN with a RST, giving `Connection refused` for ssh (the same message as a closed port; tell them apart by the access-list counter or `log` line).
Q5. Filtering guests on R1 inbound stops the traffic at the first hop, protects the R1-R2 link and R2, and needs only one router's policy, but the ACL sees guest traffic to R1's own addresses (and so needs the ND permits). Filtering on R2 needs the guests' traffic to cross R1 and the link first, wastes bandwidth, and R1's own addresses and e0/2 neighbours are reachable unless R1 also filters; it fits only when R2 is the single policy point for several sources.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a) |
