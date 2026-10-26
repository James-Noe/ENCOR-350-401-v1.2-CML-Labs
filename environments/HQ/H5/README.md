# HQ H5 stage: dual-core lite (built by MS-4)
As built for MS-4.
The stage is the **solved** MS-4 HQ part: MS-4's start state plus the proven solution of CR1-CR3 and the ticket fixes on HQ-CORE2 and HQ-EDGE2. Cold-boot tested: HQ-CORE1, HQ-CORE2 and HQ-EDGE2 were wiped, given these configs and started; the end-state checks below passed. MS-4's exported YAML is the start state, never H5.

**Profile (HQ 8; with the MS-4 attachments EDGE 4, DC 5, MGMT1 1 = 18 nodes):** HQ-CORE1, HQ-CORE2 (iol-xe), HQ-DIST1, HQ-DIST2, HQ-ACC1 (ioll2-xe), HQ-PC1 (VLAN 10), HQ-PC2 (VLAN 20, video viewer, no viewer at boot), HQ-PC3 (VLAN 50, the encoder 239.10.20.1 from boot) and the cat8000v HQ-EDGE2 as `HQ-EDGE2.c8k.cfg` for reuse (two vCPU needed for RESTCONF).

**Nodes:** HQ-CORE1/CORE2/DIST1/DIST2/ACC1, HQ-PC1/PC2/PC3, HQ-EDGE2 (cat8000v). Attachments not repeated here: HQ-EDGE1, PROV-ISP1/2 = EDGE E3 forms as adapted in MS-4 (ISP interfaces on the IX shut; PROV-ISP2 adds Loopback2 203.0.113.50/32 as the partner server and Loopback200 192.0.2.200/32 as the Internet host, originated in BGP); DC = H3 DC lite + NMS files; AUTO-MGMT1 = A2 trimmed (ens2 10.50.50.31/24, route 10.0.0.0/8 via 10.50.50.1, ens3 NAT). `MS-4.yaml` holds all of them.

## Cabling (delta from HQ lite H4)
| Link | A | B | Addressing |
|---|---|---|---|
| Core link | HQ-CORE1 e0/0 | HQ-CORE2 e0/0 | 10.10.255.0/31 (CORE1 .0), OSPF 1 area 0 p2p cost 10 hello 1 / dead 4; MGMT e0/0.99 10.10.254.2/31 (CORE1 .2, CORE2 .3), OSPF 99 |
| Straight trunk | HQ-CORE2 e0/2 | HQ-DIST2 e1/1 | VLAN 904 10.10.255.8/31 (CORE2 .8, DIST2 .9) + VLANs 20, 50, 99 (CORE2 .3) |
| CORE2-EDGE2 | HQ-CORE2 e0/3 | HQ-EDGE2 Gi2 | 10.10.255.66/31 (CORE2 .66), MGMT 10.10.254.8/31 (CORE2 .8, EDGE2 .9) |
| EDGE1-EDGE2 | HQ-EDGE1 e0/3 | HQ-EDGE2 Gi3 | 10.10.255.68/31 |
Unused and shut: CORE1 e1/0, CORE2 e0/1 and e1/0, DMZ ports. DC stays on CORE1 e1/1 (.130, as lite).

## Content (the student's CRs, solved)
- **CR1.** `ip sla 11` (CORE1, to 10.10.255.65 from e0/3) and `ip sla 12` (CORE2, to 10.10.255.67 from e0/3): frequency 2, timeout 1000, threshold 1000; `track 11/12 ip sla N reachability`; `track N shutdown` under `vrrp 20/50 address-family ipv4` on each core's VLAN subinterfaces (the 30 s `preempt delay minimum` is in the H4 base files); EEM applet `GW-EVIDENCE` on `VRRP-6-STATE:` appending clock, `show vrrp brief`, the track and the default route to `unix:gw-evidence.txt` and logging one syslog message. **Not** `track N decrement`: with the preempt delay it delays takeover to about 31 s.
- **CR2.** CORE2: `ip multicast-routing`, `ip pim rp-address 10.255.10.100`, Loopback10 10.255.10.100/32 (OSPF area 0, PIM), PIM sparse mode on Lo0, e0/0, e0/2.20, e0/2.50 (`query-interval 1`), `dr-priority 200` and `ip igmp access-group OPS-VIDEO` on e0/2.20, MSDP to 10.255.10.1 from Loopback0 with `originator-id Loopback0`. CORE1: PIM on e0/0, `dr-priority 200` on e0/1.50, MSDP to 10.255.10.2.
- **CR3.** `PM-CORE-EDGE`: `CM-OPS-APP` (`CR3-OPS` permit tcp 10.10.20.0/24 any eq 443) set dscp af21, bandwidth percent 30; `CM-BULK-XFER` (`CR3-BULK` tcp 10.10.50.0/24 eq 20 / 21) set dscp cs1, bandwidth percent 10; class-default fair-queue; `service-policy output` on e0/3 of both cores. No shaper (a test-only parent is needed to see congestion).
- **Ticket fixes on CORE2:** `logging host 10.50.50.51 vrf MGMT`, RADIUS `auth-port 1812 acct-port 1813`. HQ-DIST SVI GLBP/HSRP stays untracked (ioll2-xe has no `track`).
- **HQ-EDGE2.c8k.cfg:** E3 on the cat8000v interface map (Gi1 ISP-B, Gi2 CORE2, Gi3 EDGE1, Gi4 DMZ) with SLA 20 to 203.0.113.1, `ip nat inside` on Gi2-Gi4, `ip flow monitor FM-EDGE input` on Gi1/Gi2/Gi4, `ip http secure-server` with access class `API-HOSTS` = 10.50.50.31, `EDGE-IN-V4` numbered 10-260 with ACE 135 (permit icmp host 203.0.113.50 host 203.0.113.65 echo-reply), `CP-MGMT` permitting TCP 443 from 10.50.50.31 (otherwise CoPP `CM-UNDESIRABLE` drops the API), `PM-COPP` in the original order (CR5 amended). The certificate (`API-TP`) is made on first use by `/home/cisco/trust/fetch-edge2-cert.sh` from AUTO-MGMT1 (A1 pattern); it is not part of the file.

## Boot-check outcomes (MS-4, fresh import)
HQ-EDGE2 cold-booted from `HQ-EDGE2.c8k.cfg` (CVAC applied in about 4 minutes): track 20 Up, NAT inside Gi2-Gi4, flow monitor on three interfaces, HTTPS enabled (RESTCONF answers 401 without credentials), `EDGE-IN-V4` 130/135/140, `ping 203.0.113.50 source GigabitEthernet1` 5/5. HQ-CORE1 and HQ-CORE2: tracks 11/12 Up, VRRP 20 master CORE2, 50 and 99 master CORE1, MSDP Up, PIM DR priority 200 on CORE2 e0/2.20, RADIUS 1812/1813 UP, syslog to .51 (MGMT), `GW-EVIDENCE` registered, `PM-CORE-EDGE` on e0/3 with the OPS and BULK classes. The drills (V1-V4, V9, V10) were measured in MS-4 on the equivalent running configuration (SOLUTION.md).

**Restart rule.** After a `node stop`/`start` of HQ-EDGE2 the stored day-0 is applied again (`FILE_IGNORED ... checksum unchanged` in the log is normal; `cml-rest.sh wait` keeps reporting not-ready). Wipe the DC nodes together with DC-RTR1. Do not open HQ-EDGE2's console while its day-0 is being applied (stale session; `clear line 0` from SSH).
