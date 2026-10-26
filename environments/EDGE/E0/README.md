# EDGE E0 stage baseline (single ISP)
Built and proven in CML by LAB-024. The stage is the **solved** state of LAB-024: LAB-024's YAML is the start state (EDGE1 without BGP, NAT or default), never E0. HQ-EDGE1 is LAB-024's start config plus its solution (NAT roles, BGP, default, OSPF default origination); the other five nodes equal LAB-024's start configs. IPv4 only.

**Profile:** 8 running nodes: HQ-EDGE1, PROV-ISP1, HQ-CORE1 stub (iol-xe); PROV-SRV1, HQ-SRV1, HQ-PC1 (alpine); unmanaged switches `IX` and `DMZ` (they count as running nodes). E0 lite (EDGE1, ISP1, PROV-SRV1) is derived by the milestones, not here.

## Topology
| Link | A | B | Addressing |
|---|---|---|---|
| EDGE1-ISP1 | HQ-EDGE1 e0/0 | PROV-ISP1 e0/0 | 198.51.100.64/31 (ISP1 .64, EDGE1 .65) |
| EDGE1-core | HQ-EDGE1 e0/1 | HQ-CORE1 e0/3 | 10.10.255.64/31 (CORE1 .64, EDGE1 .65), OSPF point-to-point, cost 10, hello 1 / dead 4 |
| EDGE1-DMZ | HQ-EDGE1 e0/2 | DMZ switch | 10.10.60.2/24, HSRP 60 VIP .1 (priority 110, preempt, alone) |
| ISP1-IX | PROV-ISP1 e0/2 | IX switch | 192.0.2.193/26 |
| PROV-SRV1 | eth0 | IX | 192.0.2.200/26, gw .193 |
| HQ-SRV1 | eth0 | DMZ | 10.10.60.150/24, gw .1 |
| Stub user LAN | HQ-CORE1 e1/3 | HQ-PC1 eth0 | 10.10.10.1/24; PC1 .101 |

Loopbacks: EDGE1 10.255.10.31, CORE1 stub 10.255.10.1 (+ Lo20 10.10.20.2/24, Lo50 10.10.50.2/24, advertised as stand-ins for the campus), ISP1 198.51.100.1 and 198.51.100.10/29. Not cabled (D2/E1+): EDGE2, ISP2.

**Stub role:** HQ-CORE1 stands in for the campus core; its user LAN 10.10.10.0/24 plays the DIST role (in H2 that subnet lives on the DISTs).

## Edge content (EDGE1)
- eBGP AS 65010 to ISP-A AS 64601 (198.51.100.64), MD5 password `ISPA-64601`, router-id 10.255.10.31.
- `network` + Null0 anchors for 192.0.2.0/26 (user pool A) and 192.0.2.128/26 (DMZ). Outbound route-map ISPA-OUT (prefix-list VERIDIAN-OUT, exactly those two); inbound route-map ISPA-IN (prefix-list ISPA-IN: 198.51.100.0/25 and 198.51.100.8/29).
- Untracked static default to 198.51.100.64; OSPF `default-information originate metric 10` (no `always`), OSPF default seen on CORE1 as E2 tag 1.
- NAT: e0/0 outside, e0/1 and e0/2 inside; PAT pool POOL-A 192.0.2.1 (single address, overload) for ACL NAT-INSIDE 10.10.0.0/16; static 10.10.60.150 <-> 192.0.2.130.
- ISP1 (provider, read-only for students): AS 64601, sends 198.51.100.0/25 and 198.51.100.8/29; accepts only 192.0.2.0/24 length /24-/26 from Veridian, soft reconfiguration inbound.

## Measured behaviour (LAB-024)
- MD5 eBGP, PAT on a single-address pool with `overload`, and static NAT inbound with the Null0 /26 present (NAT before routing) all PASS on iol-xe; no fallback needed.
- Cable pull (`shutdown` both ends of EDGE1 e0/0 and ISP1 e0/0): BGP down the same second, static default and CORE1 default removed; restore: default back at once, BGP Up about 14 s later.
- Silent failure (`link stop`): session stays Up until the hold timer, about 140-170 s (140 s and 167 s measured; hold 180 s counts from the last keepalive); the static default is never removed (still present at +190 s) and the campus black-holes Internet traffic. This is the problem LAB-026..029 solve.
- Hosts: tcpdump needs root (unavailable); prove R6 with `debug ip packet detail` on ISP1 or a CML link capture.
- Start-state pings need 1 retry on the first ARP; a full `show` + ping pass takes over 120 s on this lab, so give scripted sessions a long timeout.
