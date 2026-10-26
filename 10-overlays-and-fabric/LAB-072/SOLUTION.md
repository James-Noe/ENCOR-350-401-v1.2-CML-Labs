# LAB-072 — Solution

## Summary
A night-shift integrated troubleshooting lab on the HQ H3 lite campus with the EDGE E3 edge and the DC segment. Three tickets, four faults (v1.3 adds F4), shared effects: a static EtherChannel mode mismatch between the distribution switches (F1) splits spanning tree and strands the Operations VLAN, a trunk VLAN omission on one access uplink (F2) is latent until F1 happens and then hides the access switch's management, and a "cleaned up" IPv6 Null0 route (F3) withdraws Veridian's IPv6 prefix from BGP. F4 (v1.3) is a security-review SGACL cell on HQ-CORE1 that drops the replies from SERVERS to OPERATIONS: SGACLs are stateless per direction, so the permitted OPS to SERVERS requests are answered but the replies never reach PC2. It stays invisible behind F1 until F1 is fixed. The student collects evidence with the automation host (netmiko script, Ansible), reads an unreachable device as evidence, and proves the fix with a cable-pull test (V4).

Objectives (instructor only): 3.1.a:T (trunks, VLAN 99), 3.1.b:T (EtherChannel mode mismatch), 3.2.c:T (eBGP IPv6 advertisement), IPv6:T, 3.1.c:R (root guard, loop guard, STP roots), 6.1:R (scripted evidence), 4.2:R (FNF cache as evidence), 5.1.a:R (AAA/VTY eliminated), 5.4.d:T (v1.3, group-based policy). LAB.md lists blueprint domains 3, 4, 5, 6 only.

## Intentional Faults

| ID | Device | Change | Symptom |
|---|---|---|---|
| F1 | HQ-DIST2 | Po1 members (Et0/0, Et0/1) `channel-group 1 mode on`; HQ-DIST1 stays LACP `active` | DIST2 `Po1(SU)` protocol `-`, members `(P)`; DIST1 `Po1(SD)`, members `(s)`, `%ETC-5-L3DONTBNDL2`. Interconnect carries nothing: DIST2 becomes root of every VLAN, DIST1 root-guard blocks Et0/2 for VLAN 20 (`ROOTGUARD_BLOCK`), PC2 (VLAN 20) cut off from CORE1 (TK1); DIST2's own management SVI stranded (TK3, DIST2) |
| F2 | HQ-ACC1 | `switchport trunk allowed vlan 10,20` on Et0/0 (to DIST1), VLAN 99 missing; Et0/1 keeps 10,20,99 | Latent alone. With F1: ACC1's VLAN 99 runs only to DIST2, which cannot reach CORE1: ACC1 unmanageable (TK3, ACC1). After F1 alone is fixed, ACC1 answers but loses management when Et0/1 is pulled (V4) |
| F3 | HQ-EDGE1 | `ipv6 route 2001:DB8:10::/48 Null0` removed (IPv4 Null0 kept) | BGP `network 2001:DB8:10::/48` has no RIB match; ISP1 receives no Veridian IPv6 prefix, IPv6 replies never return (TK2); IPv4 unaffected |

| F4 (v1.3) | HQ-CORE1 | `ip access-list role-based SRV-OPS` with `deny ip`, applied as `cts role-based permissions from 50 to 20 SRV-OPS` ("servers must not open sessions to Operations") | PC2 to 10.255.50.1: 100% loss while PC2 reaches its gateway and 192.0.2.200. Requests pass the 20 to 50 cell, DC-RTR1 answers, CORE1 drops each reply on the 50 to 20 cell. PC1 unaffected (no 50 to 10 cell). Masked by F1 while PC2 is cut off |

**Fault logic.** TK1 = F1 (series). TK3: DIST2 = F1; ACC1 = F1 and F2 in parallel for repair (either fix restores ACC1, the other stays latent). TK2 = F3. (v1.3) TK1 = F1 + F4 in series: after F1 alone PC2 reaches its gateway and the Internet host, but V1 still fails for PC2 to 10.255.50.1.
**Given design: DIST2 VLAN 10 OSPF cost 20.** HQ-DIST2 `interface Vlan10` carries `ip ospf cost 20` and `ospfv3 cost 20`; it is documented in LAB.md as the routing design, not a fault. It exists so the start state is boot-independent: under F1, DIST2 blocks VLAN 10 on Et0/2 (root-inconsistent), and without the cost CORE1 ECMPs 10.10.10.0/24 over both distribution switches. CEF's per-destination hash seed changes on every CORE1 boot, so PC1's return traffic from remote hosts could go via DIST2 and be black-holed (seen once after a CORE1 wipe, PC1 to remote hosts 100% loss). With the cost, CORE1 has a single path (via DIST1, metric 11), the return path is deterministic, and TK1 stays Operations-only. Proven by three CORE1 wipes.
**Red herrings.** (v1.3: the 20 to 50 OPS-SRV cell counts every request, so the forward direction is fine; the EMPLOYEES to SERVERS ICMP-only cell is restrictive but documented; DC-RTR1's routes and filters are fine, it answers PC1 and its link-sourced pings reach PC2.) `ROOTGUARD_BLOCK` logs (the guard works; DIST2 also logs VLAN 10 (and 99 with F2 fixed first) root-inconsistent on Et0/2, a pure consequence of F1: ACC1 relays DIST1's superior root BPDUs to DIST2 while the interconnect is dead; it disappears when F1 is fixed); GLBP/HSRP on the distribution pair (VLAN 10 users fine); `EDGE-IN-V6` `deny ipv6 any any log` matches (only provider RA/MLD, no echo-reply denies); CoPP; OSPFv3 default on CORE1 present; RADIUS fine (console access works).
**Wrong-fix traps.** Removing root guard from DIST1 Et0/2 (restores PC2 but breaks V5); `channel-group 1 mode on` on DIST1 too (bundle forms, protocol `-`, breaks V5); (v1.3) `no cts role-based enforcement`, removing the VLAN 20 mapping or `permit icmp` above the deny in SRV-OPS (see the trap results below); a static IPv6 default on ISP1 (not ours); `redistribute static` into BGP (advertises more than the /48, V3).

## Diagnosis / Methodology
1. **Evidence first (R1).** On AUTO-MGMT1: `cd ~/auto && /home/cisco/venv/bin/python show_cmds.py --out before` (24 s with two devices down). Captured status:
```
=== STATUS (24 s) ===
HQ-CORE1   10.10.99.2     ok
HQ-DIST1   10.10.99.11    ok
HQ-DIST2   10.10.99.12    UNREACHABLE
HQ-ACC1    10.10.99.21    UNREACHABLE
HQ-EDGE1   10.10.254.5    ok
DC-RTR1    10.50.50.1     ok
```
Both silent devices are the ones with no VLAN 99 path to CORE1 (CORE1's VRF MGMT has 10.10.99.0/24 connected, DIST1 answers, console access to both switches works: routing and AAA are fine; Q4).
2. **TK1.** PC2's port is up in VLAN 20 and ACC1 learns its MAC (host eliminated). CORE1: `show vrrp brief` VLAN 20 MASTER, but `show ip arp 10.10.20.102` empty (path problem below the gateway). DIST1 `show spanning-tree inconsistentports`: `VLAN0020 Ethernet0/2 Root Inconsistent`, and DIST1 believes it is root of VLAN 20 (priority 28692) while DIST2 is root of everything (`Root bridge for: VLAN0001, 0010, 0020, 0050, 0099, 0902`): the designed roots are not both reachable, so the STP message is a consequence. Next look at the interconnect: DIST2 `Po1(SU)` protocol `-`, DIST1 `Po1(SD)` `LACP`, `(s)` members, log `%ETC-5-L3DONTBNDL2: Et0/0 suspended: LACP currently not enabled on the remote port.` Compare both ends: the channel modes differ (F1). Removing root guard would "work" only because ACC1 would then forward as a transit between the two roots (wrong fix, V5).
3. **TK3.** `show_cmds.py` names DIST2 and ACC1. `show spanning-tree vlan 99` on ACC1: root port Et0/1 toward DIST2, root priority 28771 (DIST2); DIST1 is root of VLAN 99 with 24675. On ACC1 `show interfaces trunk`: Et0/0 allows `10,20`, Et0/1 `10,20,99` (F2). DIST2 is only unreachable because of F1; ACC1 would recover from either fix.
4. **TK2.** Local checks first: PC1 has its global address and RA default router, CORE1 has `::/0`; edge ACL/CoPP show no echo-reply denies; IPv4 FNF flows present. Then BGP: `show bgp ipv6 unicast neighbors 2001:DB8:F001:FFFF::64 advertised-routes` `Total number of prefixes 0`; `show bgp ipv6 unicast 2001:DB8:10::/48` `% Network not in table`; `show ipv6 route 2001:DB8:10::/48` matches only `::/0`. ISP1 (provider view, available in the lab) lists no Veridian prefix. The `network` statement has no matching RIB route: F3. Local evidence is enough (Q3).

**Isolation (each fix alone, cumulative state as stated):**

| Fix | Cleared | Not cleared |
|---|---|---|
| F3 alone | TK2: PC1 to 2001:db8:f001:200::200 answers 12 s after the command | TK1, TK3 |
| F2 alone (F1 present) | ACC1 10.10.99.21 answers after 9 s; ACC1 VLAN 99 root port Et0/0 | DIST2 (.12) still silent, DIST2 now also logs ROOTGUARD_BLOCK for VLAN 10 and 99 on Et0/2; PC2 gateway 0% (TK1) |
| F4 alone (F1 fixed first; F1 masks it) | PC2 to 10.255.50.1 answers about 1 s after the command (counters stop denying) | nothing for PC1; V7 still compares the matrix |
| F1 alone | PC2 gateway answers 8 s after the commands; DIST1/DIST2 `Po1(SU) LACP`, both `inconsistentports` empty; DIST2 .12 and ACC1 .21 answer (ACC1 via DIST2/Po1) | ACC1 still latent: pulling ACC1 Et0/1 strands it (V4 fails) |

5. **TK1 after F1 (F4).** PC2 reaches its gateway and 192.0.2.200 but not 10.255.50.1, while PC1 reaches it. Eliminated: host and gateway (they work for the Internet host), DC routing (PC1 works; DC-RTR1 `ping 10.10.20.102 source Ethernet0/0` (10.10.255.131) 2/2, so DC-RTR1 can reach PC2). Direction and source group: DC-RTR1 `ping 10.10.20.102 source Loopback0` (10.255.50.1) fails 0/2, the same path from a different source address (the SERVERS-mapped one). CORE1 `show cts role-based counters` shows `50 20 SW-Denied` rising with each PC2 ping reply while `20 50 SW-Permitted` rises per request. `show cts role-based permissions` lists a `from group 50 to group 20` cell (`SRV-OPS`) that the documented policy does not have: F4. (No traceroute evidence: PC2's traceroute gives the same two hops with and without F4 and does not discriminate.) The security intent (no server-initiated sessions) cannot be met by a stateless cell: it cannot tell a reply from a new session (debrief).

## Solution Configuration
**HQ-DIST2** (the members must leave the static channel first: `channel-group 1 mode active` alone is rejected with `is already part of a channel with a different type of protocol enabled`):
```
interface range Ethernet0/0 - 1
 no channel-group 1
 channel-group 1 mode active
```
**HQ-ACC1**
```
interface Ethernet0/0
 switchport trunk allowed vlan add 99
```
**HQ-EDGE1**
```
ipv6 route 2001:DB8:10::/48 Null0
```
**HQ-CORE1** (F4; the RBACL `SRV-OPS` may be left unused or removed):
```
no cts role-based permissions from 50 to 20
```
Nothing is saved to NVRAM in the build; save in production.

## Verification
All captured on a fresh import of the YAML.
- **V5 / Po1:** `HQ-DIST1: 1 Po1(SU) LACP Et0/0(P) Et0/1(P)`, `HQ-DIST2: 1 Po1(SU) LACP Et0/0(P) Et0/1(P)`; `Number of inconsistent ports (segments) in the system : 0` on DIST1. `spanning-tree vlan 10,50,99 priority 24576` and `vlan 20 priority 28672` on DIST1 (DIST2 inverse) and `spanning-tree guard root` on Et0/2 unchanged; CORE1 VRRP 20/50/99 MASTER.
- **V1:** PC1 and PC2 to their gateway, 10.255.50.1 and 192.0.2.200: 2/2 each (`0% packet loss`). PC1 to DC-AAA1 10.50.50.52 stays unreachable by design.
- **V2:** PC1 and PC2 to 2001:db8:f001:200::200: 2/2 (the first v6 ping after the fix can lose one to neighbour discovery).
- **V3:** EDGE1 IPv4 advertised `Total number of prefixes 2` (192.0.2.0/26, 192.0.2.128/26), IPv6 `Total number of prefixes 1`; ISP1 receives `2001:DB8:10::/48` only.
- **V4 / V6:** `show_cmds.py` after the fixes:
```
=== STATUS (7 s) ===   (re-imported lab: 10 s)
HQ-CORE1   10.10.99.2     ok
HQ-DIST1   10.10.99.11    ok
HQ-DIST2   10.10.99.12    ok
HQ-ACC1    10.10.99.21    ok
HQ-EDGE1   10.10.254.5    ok
DC-RTR1    10.50.50.1     ok
```
`ansible-playbook evidence.yml` (venv): `ok=2` for ACC1, DIST1, DIST2 and EDGE1 in 11 s (before the fix: 30 s, ACC1 and DIST2 `fatal ... timed out`). Netmiko reaches ACC1 through the global VLAN 99 SVI via 10.10.99.1. The `before`/`after` diff shows Po1 state, inconsistent ports, ACC1's trunk and the IPv6 BGP summary changing.

- **V1 / V7 (v1.3) captured, F1 fixed, F4 present:** PC2 to 192.0.2.200 3/3, to 10.255.50.1 `100% packet loss`; DC-RTR1 `source Loopback0` `Success rate is 0 percent (0/2)`, `source Ethernet0/0` (`10.10.255.131`) `!!`; CORE1:
```
show cts role-based permissions
IPv4 Role-based permissions from group 50 to group 20 (configured):
	SRV-OPS
IPv4 Role-based permissions from group 10 to group 50 (configured):
	EMP-SRV
IPv4 Role-based permissions from group 20 to group 50 (configured):
	OPS-SRV
show cts role-based counters
From    To      SW-Denied  HW-Denied  SW-Permitted  HW-Permitted
50      20      3          0          0             0
10      50      0          0          2             0
20      50      0          0          3             0
show ip access-lists SRV-OPS     ->  10 deny ip (5 matches)
```
After `no cts role-based permissions from 50 to 20`: PC2 to 10.255.50.1 2/2; only the 10 to 50 `EMP-SRV` and 20 to 50 `OPS-SRV` cells remain; 3 CLI bindings (10.10.10.0/24=10, 10.10.20.0/24=20, 10.255.50.1=50); `cts role-based enforcement` on; counters `10 50 permitted`, `20 50 permitted`, nothing denied. Under the healthy policy PC1 and PC2 reach 10.255.50.1, 192.0.2.200 and the IPv6 host; VRF MGMT, RADIUS, SSH from MGMT1, VRRP 99 and OSPF are unaffected (unknown-source flows).

## Failure / Recovery Behaviour
Method: cable pull = `shutdown` on both ends (ACC1 Et0/x and DIST Et0/2), then `no shutdown` on both. All fixes in place. Pings at 0.2 s (PC1 to 10.10.10.1, PC2 to 10.10.20.1, MGMT1 to 10.10.99.21); loss = lost packets x 0.2 s.

| Scenario (trigger, end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| Pull ACC1 Et0/0 and DIST1 Et0/2, end: pings steady; then restore | 0, 0, 0 lost packets on all three flows, pull and restore (plus one earlier 1 s run, 0 lost) | 0 lost at 0.2 s; allow up to ~2 s (derived: rapid-pvst proposal/agreement and MAC re-learn) | RSTP alternate port takes over on link-down; not a timer |
| Pull ACC1 Et0/1 and DIST2 Et0/2, same ends | 0, 0, 0 lost on all three flows, pull and restore | same | same |
| Same Et0/1 pull with F2 unfixed (F1 fixed) | 3/3 management pings lost until the port is restored (ACC1 answers within 2 s of restore) | management lost for the duration | ACC1's only VLAN 99 path is Et0/1 (V4 fails) |

Other timings (trigger to clean ping, a scripted CLI poll): F3 6-12 s, F2 2-9 s, F1 6-8 s, F4 fix (`no cts role-based permissions from 50 to 20`, end = first PC2 to 10.255.50.1 reply, poll 1 s): 1, 1, 1, 1 s (a later run through a fresh console session read 4 s including session set-up); re-injecting the cell to 100% loss: 2, 2 s; documented range 0-5 s, no timer involved (a config change takes effect at once). The V4 cable pull was repeated with F4 fixed (Et0/1 pulled and restored, pings PC2 to 10.255.50.1 at 0.2 s): 0 lost in three runs, one packet lost in a fourth before the trigger (ARP baseline); same result with the DIST2 VLAN 10 cost in place. Cold boot 12 nodes + NAT: BOOTED 85 s, protocols converged < 140 s, AUTO-MGMT1 tools ready about 3.5 min after start. A one-sided `shutdown` is not a cable pull (peer stays up/up); a link stop would be a silent failure and is not used here.

F4 traps (F1, F2, F3 fixed, F4 present, once each): (A) `permit icmp` above `deny ip` in SRV-OPS: an RBACL used in a cell cannot be edited (`% Role-based access list SRV-OPS could not be modified since it is used in role-based permissions`), so the cell must be removed first, the RBACL edited (ACL `10 permit icmp / 20 deny ip`) and the cell re-applied; PC2 to 10.255.50.1 then answers 2/2, so V1 passes, but the matrix is no longer the documented one and V7 fails. (B) `no cts role-based enforcement`: ping answers after 1 s; V1 passes, V7 fails (enforcement is off). (C) `no cts role-based sgt-map 10.10.20.0/24 sgt 20`: ping answers after 1 s (OPERATIONS becomes an unknown source); V1 passes, V7 fails (mapping missing). Each was reverted and the 100% loss returned in 2-3 s.

Wrong fixes tried once (F1 re-injected, F2 and F3 fixed): (A) `no spanning-tree guard root` on DIST1 Et0/2: PC2 gateway answers after 9 s but `Po1(SD)` stays; breaks V5. (B) DIST1 members `no channel-group 1` / `channel-group 1 mode on`: `Po1(SU)` protocol `-` on both ends, PC2 answers after 8 s; breaks V5 (LACP is the standard). The correct fix on both ends gave `Po1(SU) LACP`.

## Answers to Analysis Questions
**Q1** Order by what the "before" set showed. The two silent devices (ACC1, DIST2-side path) and the Layer 2 evidence came first, because a dead interconnect explains TK1 and TK3 together; TK2 is an independent IPv6 BGP issue. Specifically: `show spanning-tree inconsistentports` pointed at root guard, but the roots were wrong network-wide (DIST2 root of every VLAN, DIST1 root of VLAN 20 by itself): the interconnect was not forwarding. `show etherchannel summary` on both ends (modes differ, `L3DONTBNDL2`) is the cause; the STP messages were a consequence (after fixing the bundle both inconsistent lists were empty with no STP change).
**Q2** Re-run the evidence set and diff it against "before" (V6), ping all flows (V1, V2), check `inconsistentports` and `show etherchannel summary` (V5), BGP advertisements (V3), and cable-pull each ACC1 uplink (V4). F1 closed TK1 and, through the DIST2/Po1 path, both halves of TK3; the remaining risk (F2, a trunk that does not carry VLAN 99 to DIST1) only shows when the ACC1-DIST2 uplink is lost, so only the backup-path test (V4) or comparing both uplinks' `show interfaces trunk` finds it.
**Q3** For TK2 the provider side cannot be inspected, so rely on local evidence: zero advertised prefixes for the neighbour (`show bgp ipv6 unicast neighbors ... advertised-routes`), `/48` not in the BGP table, no RIB route for the `network` statement, and no deny hits for replies. This is enough because the missing advertisement originates locally; the provider-side confirmation would be `show bgp ipv6 unicast` on ISP1 showing no Veridian prefix.
**Q4** The job reached the devices over the same VLAN 99 that failed, so it lost exactly the devices that needed fixing. Out-of-band paths (console server, a separate management port or network) keep management working during a Layer 2 failure; here the CML console was the out-of-band path, and the unreachable list was the symptom report. Reading which devices were silent (those with no VLAN 99 path to CORE1) located the fault domain before any device was opened.

**Q5** F1 (TK1/TK3): L2 forwarding was lost both ways; evidence is the bundle state and the STP root. F3: the requests left and the replies never came back (the provider had no route for them); evidence is empty advertised-routes and a missing RIB route. F4: the requests reached the server, the replies were dropped at HQ-CORE1's egress to VLAN 20; evidence is DC-RTR1's sourced pings (Loopback0 fails, link address works), `50 20 SW-Denied` rising per reply with `20 50 SW-Permitted` rising per request, and a 50 to 20 cell in `show cts role-based permissions`. Debrief: SGACLs are stateless per direction, so a deny cell for the reverse pair drops replies; the intent "servers must not open sessions" needs a stateful device. Compare TK2, where replies were also lost, but because the provider had no route.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-25 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), external_connector, iol-xe (IOS XE 17.16.1a), ioll2-xe (IOS XE 17.16.1a), radius, ubuntu (Ubuntu 24.04), unmanaged_switch |
