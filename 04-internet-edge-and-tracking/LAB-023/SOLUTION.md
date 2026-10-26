# LAB-023 — Solution

## Summary

Foundation lab for NAT on an edge router with two providers: inside/outside roles, static NAT (inbound reachability), dynamic pool NAT and pool exhaustion, PAT on a pool, route-map NAT with `match ip address` plus `match interface` for two exits, and the NAT debug and show commands. Blueprint 3.3.b:I, SK-RM:R (route-maps). Platform note: `match interface` route-maps work on iol-xe with two outside interfaces; the `match ip next-hop` fallback was not needed.

Build notes: (1) provider ACL `LG-INGRESS` on R2/R3 e0/0 ingress is the R5 looking glass (show-only counters); (2) PC1 has secondary addresses .111/.112 and SRV1 runs httpd on port 80 in day-0, needed for TCP port multiplexing and a three-host pool exhaustion; (3) 8 licensed nodes, because the two unmanaged switches (INET, LAN) count against the licence; (4) single-address PAT pools (198.51.100.1, 203.0.113.1), static NAT .10, exhaustion pool .20-.21.

## Intentional Faults

None (foundation lab).

## Diagnosis / Methodology

Not a troubleshooting lab. Starting-state evidence: `ping 192.0.2.100 source 10.0.10.1` from R1 fails 0/2 and PC1/PC2 pings fail, because provider ingress filtering (`LG-INGRESS` deny counter rises) and missing routes back to RFC 1918 space. R1's own pings to SRV1 and 192.0.2.129 work (sources 198.51.100.34 / 203.0.113.34).

## Solution Configuration

R1 only (providers unchanged):

```
interface Ethernet0/2
 ip nat inside
interface Ethernet0/0
 ip nat outside
interface Ethernet0/1
 ip nat outside
ip nat inside source static 10.0.10.102 198.51.100.10
ip access-list extended NAT-USERS
 permit ip 10.0.10.0 0.0.0.255 any
ip nat pool POOL-A 198.51.100.1 198.51.100.1 netmask 255.255.255.224
ip nat pool POOL-B 203.0.113.1 203.0.113.1 netmask 255.255.255.224
route-map NAT-A permit 10
 match ip address NAT-USERS
 match interface Ethernet0/0
route-map NAT-B permit 10
 match ip address NAT-USERS
 match interface Ethernet0/1
ip nat inside source route-map NAT-A pool POOL-A overload
ip nat inside source route-map NAT-B pool POOL-B overload
```

Pool exhaustion step (R4):

```
clear ip nat translation *
no ip nat inside source route-map NAT-A pool POOL-A overload
ip nat pool POOL-X 198.51.100.20 198.51.100.21 netmask 255.255.255.224
ip nat inside source list NAT-USERS pool POOL-X
```
Return to PAT:
```
clear ip nat translation *
no ip nat inside source list NAT-USERS pool POOL-X
no ip nat pool POOL-X
ip nat inside source route-map NAT-A pool POOL-A overload
```

Limited debug (R5): `access-list 11 permit 10.0.10.0 0.0.0.255` then `debug ip nat 11`. A numbered extended ACL gives `% Invalid access list name`: `debug ip nat` takes a standard ACL.

## Verification

Static NAT only (R1): SRV1 `ping 198.51.100.10` 2/2; PC2 to SRV1 works with no extra route on R1:
```
icmp 198.51.100.10:2 10.0.10.102:2 192.0.2.100:2 192.0.2.100:2
--- 198.51.100.10 10.0.10.102 --- ---     (static, 1 static)
```
Route-map PAT, both exits at once (V2, V3):
```
icmp 198.51.100.1:1024 10.0.10.101:3   192.0.2.100:3   192.0.2.100:1024   (exit A)
icmp 203.0.113.1:1024  10.0.10.101:4   192.0.2.129:4   192.0.2.129:1024   (exit B)
icmp 203.0.113.1:1025  10.0.10.101:5   192.0.2.129:5   192.0.2.129:1025
tcp  198.51.100.10:47634 10.0.10.102:47634 192.0.2.100:80 192.0.2.100:80   (PC2 static: same port, global .10)
```
Port multiplexing (two wgets from PC1, `wget http://192.0.2.100/` returns `web-ok`): `tcp 198.51.100.1:1024 10.0.10.101:33886` and `tcp 198.51.100.1:1025 10.0.10.101:33902`. `show ip nat statistics`: `[Id: 1] route-map NAT-A pool POOL-A refcount 2`, `[Id: 2] route-map NAT-B pool POOL-B`. `ping -I 10.0.10.111 192.0.2.129` gives `icmp 203.0.113.1:1024 10.0.10.111:6`.

Debug (V4/R5):
```
NAT*: s=10.0.10.101->198.51.100.1, d=192.0.2.100 [8678]
NAT*: s=192.0.2.100, d=198.51.100.1->10.0.10.101
```
Looking glass (V6): R2 `LG-INGRESS` `10 deny 10/8` counter stayed at 6 (from the pre-NAT attempts) while the permit counter rose 6 to 28 during the wgets; R3's deny line has no matches.

Pool exhaustion (V4): with POOL-X (.20-.21), .101 -> 198.51.100.20, .111 -> 198.51.100.21, .112 fails 100% loss:
```
%IPNAT-4-ADDR_ALLOC_FAILURE: Address allocation failed for 10.0.10.112, pool POOL-X might be exhausted
NAT: translation failed (A), dropping packet s=10.0.10.112 d=192.0.2.100
```
Dynamic non-overload entries are per host (`--- 198.51.100.20 10.0.10.101` persists). Side effect observed with the ACL-only rule: .101 to 192.0.2.129 (exit B) was also translated to 198.51.100.20, so A's address left through B (Q1). After returning to PAT, translations work again.

## Failure / Recovery Behaviour

Method: cable pull (`shutdown` on R1 e0/0 and R2 e0/0). Before: `icmp 198.51.100.1:1024 10.0.10.101:11`, `tcp 198.51.100.1:1024 10.0.10.101:40458`. After the pull R1's default is `via 203.0.113.33, distance 5`; PC1 ping and wget to SRV1 work with new entries `icmp 203.0.113.1:1024` and `tcp 203.0.113.1:1024` (B's address; SRV1's reply returns R2 -> R3 -> R1 over the Internet LAN). Old exit-A entries remain (icmp until its ~60 s timeout, tcp default 24 h).

**Observed limitation: PC2's static NAT fails 100% while exit A is pulled.** Static NAT is not exit-aware: the packet leaves via B but sourced from 198.51.100.10 (provider A's space), and the reply goes to R2, which has lost its route to 198.51.100.0/27. This is real behaviour, not a lab defect. It is the teaching point for Q4 and for failover with two providers (029) and NAT faults (030): fixed inbound addresses need their provider's path, or a design that fails the address over too.

Recovery: `no shutdown` on both ends restores the default via 198.51.100.33 (distance 1); after `clear ip nat translation *` PC1 uses 198.51.100.1:1024 and PC2 198.51.100.10 again.

## Answers to Analysis Questions

Q1. An ACL-only rule matches every inside source regardless of the exit, so one pool applies to all traffic (observed: .101 to 192.0.2.129 got A's address .20 while leaving through B). `match interface` tests the egress interface chosen by routing, so route-map NAT-A applies to traffic leaving e0/0 and NAT-B to e0/1, each with its own provider's pool.
Q2. Inbound (outside to inside): translate first, then route. Outbound (inside to outside): route first, then translate. For PC2's static NAT the packet from SRV1 for 198.51.100.10 is translated to 10.0.10.102 before the routing lookup, and R1 has a connected route for 10.0.10.0/24, so no route for the public address is needed (the provider routes 198.51.100.0/27 to R1).
Q3. Return traffic never reaches R1: replies to a pool address go to the wrong place or are dropped, so sessions time out (observed when PC2's static address left via B while R2 had no route to A's range during the pull).
Q4. A translation entry is created when the session starts and is kept until its timeout, independent of later routing changes: old exit-A entries stayed (tcp 24 h default) until `clear ip nat translation *`. New sessions are translated per the new egress interface. PC2's static NAT does not follow the exit, so it broke while A was pulled; failover designs must consider the NAT state and the provider's return route, not only the default route.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), unmanaged_switch |
