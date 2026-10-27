# LAB-031 — Solution

## Summary
First lab of the path-virtualization family. Two tenants (RED, BLUE) with identical prefixes share three iol-xe routers over dot1q subinterfaces; RED uses a per-VRF OSPF process, BLUE uses statics with floating backups. Proves isolation, the VRF-aware tools, and that statics do not react to failures that OSPF handles (blueprint 2.2.a). Platform note: per-VRF OSPF on subinterfaces works alongside global OSPF on the untagged main interface of the same port (no native dot1q 1 subinterfaces needed).

## Intentional Faults
None (F lab). The address-removal pitfall (Q1) is met naturally in R1.

## Diagnosis / Methodology
Not a troubleshooting lab. Method: build per router in order (vrf definition, then per interface `encapsulation dot1q`, `vrf forwarding`, `ip address`); check each VRF's neighbours and routes with the `vrf` keyword every time; a plain `show`/`ping` reads the global table. Pitfall observed: R1 `ping 10.0.3.10` (global) 0/2 although both PCs answer; R1 `ping vrf BLUE 10.0.3.10` without `source` 0/3 (source is the transit /31 10.0.212.0, which R3 cannot route back to), with `source Ethernet0/2` 3/3. RED unsourced works because OSPF carries the transit /31s.

## Solution Configuration
Applied per router in config mode (tested as one block per router; `/31` on BLUE gives the harmless warning "use /31 mask on non point-to-point interface cautiously").

### R1
```
vrf definition RED
 address-family ipv4
 exit-address-family
vrf definition BLUE
 address-family ipv4
 exit-address-family
interface Ethernet0/0.10
 encapsulation dot1q 10
 vrf forwarding RED
 ip address 10.0.112.0 255.255.255.254
 ip ospf network point-to-point
 ip ospf 2 area 0
interface Ethernet0/0.20
 encapsulation dot1q 20
 vrf forwarding BLUE
 ip address 10.0.212.0 255.255.255.254
interface Ethernet0/3.10
 encapsulation dot1q 10
 vrf forwarding RED
 ip address 10.0.113.0 255.255.255.254
 ip ospf network point-to-point
 ip ospf 2 area 0
 ip ospf cost 100
interface Ethernet0/3.20
 encapsulation dot1q 20
 vrf forwarding BLUE
 ip address 10.0.213.0 255.255.255.254
interface Ethernet0/1
 vrf forwarding RED
 ip address 10.0.1.1 255.255.255.0
 ip ospf 2 area 0
interface Ethernet0/2
 vrf forwarding BLUE
 ip address 10.0.1.1 255.255.255.0
router ospf 2 vrf RED
 router-id 10.255.0.1
 passive-interface Ethernet0/1
ip route vrf BLUE 10.0.3.0 255.255.255.0 10.0.212.1
ip route vrf BLUE 10.0.3.0 255.255.255.0 10.0.213.1 200
```
### R2
```
vrf definition RED
 address-family ipv4
 exit-address-family
vrf definition BLUE
 address-family ipv4
 exit-address-family
interface Ethernet0/0.10
 encapsulation dot1q 10
 vrf forwarding RED
 ip address 10.0.112.1 255.255.255.254
 ip ospf network point-to-point
 ip ospf 2 area 0
interface Ethernet0/0.20
 encapsulation dot1q 20
 vrf forwarding BLUE
 ip address 10.0.212.1 255.255.255.254
interface Ethernet0/1.10
 encapsulation dot1q 10
 vrf forwarding RED
 ip address 10.0.123.0 255.255.255.254
 ip ospf network point-to-point
 ip ospf 2 area 0
interface Ethernet0/1.20
 encapsulation dot1q 20
 vrf forwarding BLUE
 ip address 10.0.223.0 255.255.255.254
router ospf 2 vrf RED
 router-id 10.255.0.2
ip route vrf BLUE 10.0.1.0 255.255.255.0 10.0.212.0
ip route vrf BLUE 10.0.3.0 255.255.255.0 10.0.223.1
```
### R3
```
vrf definition RED
 address-family ipv4
 exit-address-family
vrf definition BLUE
 address-family ipv4
 exit-address-family
interface Ethernet0/0.10
 encapsulation dot1q 10
 vrf forwarding RED
 ip address 10.0.123.1 255.255.255.254
 ip ospf network point-to-point
 ip ospf 2 area 0
interface Ethernet0/0.20
 encapsulation dot1q 20
 vrf forwarding BLUE
 ip address 10.0.223.1 255.255.255.254
interface Ethernet0/3.10
 encapsulation dot1q 10
 vrf forwarding RED
 ip address 10.0.113.1 255.255.255.254
 ip ospf network point-to-point
 ip ospf 2 area 0
 ip ospf cost 100
interface Ethernet0/3.20
 encapsulation dot1q 20
 vrf forwarding BLUE
 ip address 10.0.213.1 255.255.255.254
interface Ethernet0/1
 vrf forwarding RED
 ip address 10.0.3.1 255.255.255.0
 ip ospf 2 area 0
interface Ethernet0/2
 vrf forwarding BLUE
 ip address 10.0.3.1 255.255.255.0
router ospf 2 vrf RED
 router-id 10.255.0.3
 passive-interface Ethernet0/1
ip route vrf BLUE 10.0.1.0 255.255.255.0 10.0.223.0
ip route vrf BLUE 10.0.1.0 255.255.255.0 10.0.213.0 200
```

## Verification
Captured in a test run (CML 2.10.0, iol-xe); lines trimmed.
- R1 `show ip ospf 2 neighbor`: FULL on Ethernet0/0.10 and Ethernet0/3.10; global `show ip ospf neighbor`: FULL on Ethernet0/0 and Ethernet0/3 (coexistence of global and per-VRF OSPF on one port).
- R1 `show ip route vrf RED`: `O 10.0.3.0/24 [110/30] via 10.0.112.1, Ethernet0/0.10`. `show ip route vrf BLUE`: `S 10.0.3.0/24 [1/0] via 10.0.212.1`. `show ip route | include 10.0.[13].0/24`: empty.
- Pings PC1-PC3, PC2-PC4, PC3-PC1, PC4-PC2 all answered (ttl 42).
- Isolation: PC3 MAC 52:54:00:b2:2a:18, PC4 MAC 52:54:00:4c:68:6c. R3 `show ip arp vrf RED`: `10.0.3.10 ... 5254.00b2.2a18` (PC3); `vrf BLUE`: `... 5254.004c.686c` (PC4). PC1's pings to 10.0.3.10 are answered only by PC3; R3 has no ARP for 10.0.1.x in any table. (MACs differ on every build; compare the pattern.)
- R2 `traceroute vrf RED 10.0.3.10`: hop 1 10.0.123.1, hop 2 10.0.3.10; `vrf BLUE`: hop 1 10.0.223.1, hop 2 10.0.3.10. `show ip cef vrf RED 10.0.3.10`: `10.0.3.0/24 nexthop 10.0.123.1 Ethernet0/1.10`; BLUE: `nexthop 10.0.223.1 Ethernet0/1.20`.
- SSH: `ssh -vrf RED -l admin 10.0.123.1` from R2 reaches R3's `Password:` prompt (typed by hand it logs in). Left unattended the client prints `% Password: timeout expired!` / `[Connection to 10.0.123.1 aborted: error status 0]` after 60 s. While waiting, R3 `show ssh` listed `0 2.0 IN ... Keys exchanged admin`. The login itself was not scripted (interactive password); the key exchange and prompt were captured.

## Failure / Recovery Behaviour
Continuous pings from the four PCs at 0.2 s; gap = lost packets x 0.2 s. Ping gaps are measured on the PCs, so a busy CML server does not distort them.

**(a) Cable pull R1-R2 (shutdown e0/0 on both ends).** R1 logged `OSPF Process 2 ... FULL to DOWN, Interface down` at once.
- RED: PC1-to-PC3 lost 1 packet (under 1 s), PC3-to-PC1 lost 0. New routes: R1 `O 10.0.3.0/24 [110/110] via 10.0.113.1 Ethernet0/3.10`; R2 `O 10.0.1.0/24 [110/120] via 10.0.123.1`; R3 `O 10.0.1.0/24 [110/110] via 10.0.113.0`.
- BLUE: broken in both directions until restore. R1's floating static took over (`S 10.0.3.0/24 [200/0] via 10.0.213.1`), so requests reach PC4 via the backup link; R2's static to 10.0.1.0/24 left with its interface (no route) and R3 still has `S 10.0.1.0/24 [1/0] via 10.0.223.0`, so the replies die at R2.
- Restore (no shutdown on both ends): BLUE answers again; RED costs return to the primary path.

**(b) Silent failure of R1-R2** (`tools/cml-rest.sh link stop`): global OSPF 1 and RED OSPF 2 each logged `Dead timer expired` (dead interval 40 s, which expires 40 s after the last hello, i.e. 30-40 s after the link stops; the measured gap is 31-33 s). PC1-to-PC3 and PC3-to-PC1 each had a gap of 167 packets (about 33 s). BLUE: no recovery (R1 still `S ... [1/0] via 10.0.212.1`, no floating takeover; 0 replies for the whole test). Restore with `link start`: all four PCs answered about 50 s later. RED uses the default 10/40 s hello/dead on point-to-point; a student measures 30-45 s.

## Answers to Analysis Questions
Q1. `vrf forwarding` moves the interface into another table, and an address in the old table cannot survive there (it could overlap an existing one), so IOS removes it (`% Interface ... IP address removed due to enabling VRF`). Order: `vrf forwarding` first, then `ip address`.
Q2. R2 receives an 802.1Q frame on e0/0; the tag (10 or 20) selects the subinterface, which is bound to a VRF; the IP lookup then happens in that VRF's table only (and its ARP and CEF tables). Identical addresses never meet because every table and subinterface is separate: tag 10 -> e0/0.10 -> RED, tag 20 -> e0/0.20 -> BLUE.
Q3. A plain `ping` uses the global table, which has no route to 10.0.3.0/24 (only transit /31s and loopbacks), so the packet is not forwarded; the PCs answer only when asked through a VRF. BLUE needs `source` because without it the source is the transit /31 on the egress interface (10.0.212.0), and R3 has no BLUE route back to a transit /31 (only the LANs have statics). RED works unsourced because OSPF advertises the transit /31s.
Q4. Cable pull: R1's floating static activates (the interface went down) and the request reaches PC4 via R3, but the reply goes from R3 via its primary static to R2, which lost its route to 10.0.1.0/24 when its own interface left, so it is dropped. Silent failure: no interface goes down, so no static is withdrawn on either end and traffic keeps being sent into the dead link. Fixes: tracked statics at both ends (IP SLA + track, as in lab 026), or a dynamic protocol (per-VRF OSPF or BGP as for RED).
Q5. Every router on the path needs the VRFs, a subinterface (or link) per VRF and per link, and a routing process or statics per VRF: the configuration grows with sites x VRFs x links, hop by hop. MPLS L3VPN with MP-BGP (labs 050/069) keeps VRFs only on the edge routers and carries tenant routes in the core with labels; VXLAN/EVPN fabrics do the same inside a data centre.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a) |
