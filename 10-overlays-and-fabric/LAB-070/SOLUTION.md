# LAB-070 — Solution

## Summary

Educational intent: hands-on TrustSec building blocks on a campus where the platform shows only part of the mechanism, so the student learns both the model and exactly where an emulator stops. Classification (static IP-to-SGT bindings), propagation configuration (`cts manual`, `policy static sgt 2 trusted`), SGACL matrix and egress enforcement are built and tested; the missing pieces (CMD on the wire, switched-traffic enforcement, SXP) are stated as facts, and the source-group problem becomes the teaching point: the enforcing hop (HQ-CORE1) sees an unknown source until it has bindings, which stand in for ISE/SXP. MACsec vs IPsec is analysis (MACsec rejected on this server). Blueprint: 5.4.d (introduced), 1.3.a (policy plane, reinforced). Stage written: `environments/HQ/H-TS/`.

Platform limits: ACC1 egress enforcement impossible (ioll2-xe does not enforce switched traffic); no CMD capture (a question); R3 = unknown source at CORE1; R4 = static bindings on CORE1 as the ISE/SXP stand-in; SXP never connects; R4 failure-path lines identical because CORE1 routes every flow.

## Intentional Faults

None (feature lab). Start-state note: HQ-ACC1 Ethernet1/2 (old PC5 port) is `shutdown`; HQ-PC3 serves `httpd -p 80`.

## Diagnosis / Methodology

Not a troubleshooting lab. The evidence path the student follows in R3: configure SGACLs + enforcement on CORE1, ping/wget PC1 -> PC3 (all pass), `show cts role-based counters` (all 0), `show cts role-based sgt-map all` on CORE1 (empty): the enforcing device has no source group. ACC1 knows the groups (its binding table) but `show cts interface` Propagate Enabled is configuration only: a capture on the trunk shows no 0x8909 and ACC1 counters stay 0, so nothing carries or enforces by tag. The routed hop keys only on its own bindings, hence R4.

## Solution Configuration

R1 (HQ-ACC1):
```
cts role-based sgt-map 10.10.10.101 sgt 10
cts role-based sgt-map 10.10.20.102 sgt 20
cts role-based sgt-map 10.10.50.103 sgt 50
```
R2 (HQ-ACC1 e0/0, e0/1; HQ-DIST1 and HQ-DIST2 e0/2). Port-channel members must leave the bundle first (CTS is rejected on a bundled member and on Port-channel1), on both DISTs. Re-adding a CTS-configured member to a live Po1 is rejected (`Command rejected: conflicts with CTS incompatibility detected on interface`, re-check P16-070-1), so a one-member-at-a-time change does not work: CTS on a bundle member must match the bundle, and the bundle cannot carry a mixed member while it is up. The working order dissolves Po1 on both DISTs, so plan a short Po1 outage and a change window: measured in one run, Po1 was down about 5 s, and hosts in VLANs 10, 20 and 50 lost 4-5 one-second probes in a single burst of about 6 s while STP reconverged. Users see a short interruption, not zero loss, even though the ACC1 uplinks and the VLAN failover described under the failure path carry traffic afterwards (single run, not repeated). Order: (1) `no channel-group 1` on both members on both DISTs, (2) `cts manual` + `policy static sgt 2 trusted` on every member, (3) `channel-group 1 mode active` on both members on both DISTs, then check `show etherchannel summary` shows Po1 (SU) with both members (P):
```
interface Ethernet0/0 ; interface Ethernet0/1      (ACC1, DIST1 e0/2, DIST2 e0/2)
 cts manual
  policy static sgt 2 trusted
! DIST1 and DIST2, step 1: both members out (Po1 goes down)
interface range Ethernet0/0 - 1
 no channel-group 1
! step 2: CTS on each member
interface range Ethernet0/0 - 1
 cts manual
  policy static sgt 2 trusted
! step 3: only now rejoin the bundle (both members, both DISTs)
interface range Ethernet0/0 - 1
 channel-group 1 mode active
```
R3 (HQ-CORE1, and the same lines on HQ-ACC1 plus `cts role-based enforcement vlan-list 10,20,50`):
```
ip access-list role-based WEB-ONLY
 permit tcp dst eq 80
 deny ip
ip access-list role-based PING-WEB
 permit icmp
 permit tcp dst eq 80
 deny ip
ip access-list role-based DENY-ALL
 deny ip
cts role-based permissions from 10 to 50 WEB-ONLY
cts role-based permissions from 20 to 50 PING-WEB
cts role-based permissions from 10 to 20 DENY-ALL
cts role-based permissions from 20 to 10 DENY-ALL
cts role-based enforcement
```
R4 (HQ-CORE1):
```
cts role-based sgt-map 10.10.10.101 sgt 10
cts role-based sgt-map 10.10.20.102 sgt 20
cts role-based sgt-map 10.10.50.103 sgt 50
```
IP ACL comparison (derived, not applied): on CORE1 about 8 lines for 3 hosts (`permit tcp host .101 host .103 eq 80`, `deny ip host .101 host .103`, `permit icmp host .102 host .103`, `permit tcp host .102 host .103 eq 80`, `deny ip host .102 host .103`, `deny ip host .101 host .102`, `deny ip host .102 host .101`, `permit ip any any`), applied to the right interfaces and directions; lines grow with host pairs, and a new HQ-PC2 address means editing five lines. SGACL: 3 role-based ACLs, 4 permission cells, 3 bindings, and a new address changes two bindings here (the classifier on HQ-ACC1 and the enforcer on HQ-CORE1; ACC1's binding has no effect on this platform), still independent of the policy lines. With ISE/SXP it is zero manual edits: the binding follows authentication.

## Verification

Captured on a fresh import of the YAML (trimmed).

Start (no CTS): `show cts interface brief` and `show running-config | include cts` on ACC1 empty; PC1 -> PC3 ping 3/3 and `HQ-PC3 web`.

R1/V1, ACC1 `show cts role-based sgt-map all`:
```
10.10.10.101   10   CLI
10.10.20.102   20   CLI
10.10.50.103   50   CLI
Total number of CLI bindings = 3
```
R2/V2, ACC1 and DIST `show cts interface Ethernet0/0`: `CTS is enabled, mode: MANUAL`, `IFC state: OPEN`, `Authorization Status: SUCCEEDED`, `Peer SGT: 2`, `Peer SGT assignment: Trusted`, `Propagate SGT: Enabled` (same on ACC1 e0/1; DIST1 and DIST2 e0/0, e0/1, e0/2). Both DISTs: `1  Po1(SU)  LACP  Et0/0(P)  Et0/1(P)`; `show cts interface` Port-channel1: `CTS is disabled.`

R3/V3 (enforcement on CORE1 and ACC1, no bindings on CORE1): PC1 -> PC3 ping 3/3 and web OK, PC1 -> PC2 ping 3/3, PC2 -> PC3 ping 3/3, PC2 -> PC1 ping 3/3. CORE1 counters, all cells `0 0 0 0` (From 20/To 10, 10/20, 10/50, 20/50); CORE1 `show cts role-based sgt-map all` lists no bindings; ACC1 counters all 0.

R4/V4 (bindings on CORE1; `clear cts role-based counters`, then PC1 ping/web/ping PC2, PC2 ping/web/ping PC1, PC3 ping PC1):
```
PC1 -> PC3 ping 0/3, web OK     PC1 -> PC2 ping 0/3
PC2 -> PC3 ping 3/3, web OK     PC2 -> PC1 ping 0/3     PC3 -> PC1 ping 0/3
From  To  SW-Denied  HW-Denied  SW-Permitted  HW-Permitted
20    10  3          0          0             0
10    20  3          0          0             0
10    50  6          0          5             0
20    50  0          0          8             0
```
10->50: 5 permitted = the web request packets of one wget, 6 denied = 3 pings from PC1 + 3 echo replies when PC3 pings PC1 (stateless: a reply is a 10 -> 50 ICMP cell, hence PC3 -> PC1 ping fails by design; the web replies are 50 -> 10, default permit, no counter). 20->50 permitted 8 = 3 pings + 5 web packets. 10->20 and 20->10 denied 3 each = the three pings each way. ACC1 counters stay 0.

R6/V5: see below; with the cable pulled PC1 -> PC3 ping 0/3, web OK, PC2 -> PC3 ping and web OK, PC2 -> PC1 0/2; counters 20-10 D2, 10-50 D3 P5, 20-50 P8 (same cells, via DIST2 and Po1).

R7/V6: CML capture on HQ-DIST1 e0/2 - HQ-ACC1 e0/0 with filter `ether proto 0x8909` during PC1 -> PC3 traffic: 0 frames. Unfiltered: only 0x8100 dot1q (VLANs 10/20/50/99 plus STP/CDP/IGMP). Taken through the CML REST capture API (the UI capture is the student tool).

Platform tests: ACC1 `enforcement vlan-list` leaves every counter at 0 with permissions defined; DIST1 enforcement on routed hop works only with bindings; SXP speaker ACC1 (10.10.99.21) to listener CORE1 (10.10.99.2) `Conn status: Off` 4+ min, password default and `none`; CORE1 `cts manual` rejected on Ethernet0/1.50, accepted on Ethernet0/1 but IFC INIT; `cts manual` on a bundled member rejected ("first remove from port channel").

## Failure / Recovery Behaviour

Cable pull = `shutdown` on HQ-ACC1 e0/0 and HQ-DIST1 e0/2 (VLANs 10, 50 and 99, rooted at DIST1, move to the alternate port e0/1, Altn BLK -> Root FWD; VLAN 20, rooted at DIST2, already used it. The probe measures VLAN 50; Q4 uses VLAN 10). PC3 -> 10.10.50.2 `ping -c 1 -W 1` repeated by `--every 1 --until '1 packets received'` after the config block.

| Scenario (trigger -> end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| ACC1 e0/0 + DIST1 e0/2 `shutdown` -> first PC3 -> 10.10.50.2 probe answered | 2 s, 2 s, 2 s (1 probe each; CLI floor 2 s) | 0-2 s (zero or one lost probe) | rapid-PVST alternate port switches at once; probes are 1 s apart |

All policy lines (Verification, R6) hold unchanged over DIST2/Po1 because CORE1 classifies by IP address and routes every flow. Restore: `no shutdown` on both ends; ACC1 e0/0 returns to Root FWD. Cold boot of this 9-node profile: 77 s, 88 s, 118 s (stage), VRRP MASTER on CORE1.

## Answers to Analysis Questions

Q1. Classification happens once, at the edge, by identity; enforcement sits where the destination's policy is known, so one cell (source group, destination group) replaces a per-port, per-address ACL on every ingress. Adding a host means one binding, not edits in many ACLs.

Q2. ISE classifies dynamically at 802.1X/MAB (replacing the static bindings on ACC1), holds the matrix centrally and pushes SGACLs to every enforcer (replacing the per-device `permissions` lines), and SXP/pxGrid distribute bindings to devices that cannot tag (replacing the static bindings on CORE1). Here every one of those is typed by hand.

Q3. In SD-Access the SGT travels in the VXLAN-GPO header between fabric nodes (069, derived: not testable here), so the edge classifies and the egress node enforces with no per-hop propagation; it replaces the trunk `cts manual` + CMD.

Q4. CORE1 sees the source group from its own IP-to-SGT binding for 10.10.10.101 (group 10), not from any tag, so the L2 path does not matter: the frame arrives through DIST2/Po1 instead of DIST1, the packet is routed, the lookup is by address, and the counters are the same cells.

Q5. 

| | MACsec (802.1AE) | IPsec |
|---|---|---|
| Layer | 2 | 3 |
| Scope | hop-by-hop (each link decrypts/re-encrypts) | end-to-end between peers |
| Key exchange | MKA (802.1X-EAP, or PSK/CAK) | IKE |
| Protects | whole Ethernet payload on one link, line rate, hardware | IP payload (ESP), tunnel or transport mode |
| Leaves visible | MAC addresses, the outer frame header (the MACsec header carries the SCI) | outer IP header (tunnel mode), ports in transport mode are encrypted |
| Fits | a campus trunk (hardware, no routing needed, switch sees plaintext at each hop) | the WAN (crosses untrusted routed paths, peers across L3) |

Not demonstrable here: `macsec` is rejected on the emulated switches (a CML platform limit).

Q6. On real hardware the CMD header sits inside the Ethernet frame after the source MAC, with EtherType 0x8909, carrying the 16-bit SGT, about 8 bytes plus an optional ICV. Here `show cts interface` reports Peer SGT 2/Propagate Enabled, but ioll2-xe never emits CMD (only 0x8100 dot1q is seen), so the configuration is right and the emulation lacks the data path.

Q7. A real access switch enforces SGACLs on egress toward the destination, in hardware, using the source group from the CMD tag or its own binding, so same-switch and routed-back flows would show `From 10 to 50` cells on ACC1 and the enforcement would not depend on a routed hop. Here ioll2-xe enforcement is configuration only, so only the routed hop (CORE1) filters and counts, and it needs its own bindings because no tag arrives.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a), radius |
