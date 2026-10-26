# LAB-054 — Solution

## Summary

Foundation lab for module 08: IGMP membership, PIM sparse mode with a static RP, the life of one stream (register, register-stop, SPT switchover), `spt-threshold infinity`, RPF, and IGMPv2 against IGMPv3. Blueprint 3.3.d:I. The bench is the FND T-MC environment (4 iol-xe routers, 2 alpine hosts). Multicast is routed only on routers (ioll2-xe is not used).

Platform notes (iol-xe 17.16, alpine iperf 2.2.0):
- `(S,G,rpt)` is **not** a separate line in `show ip mroute` on iol-xe. The prune of the source from the shared tree shows as the R2 `(S,G)` entry with flags `PT` and an empty outgoing list, plus the `debug ip pim` line `Prune-list: (10.0.1.10/32, 239.1.1.x) RPT-bit set`.
- `show ip mroute count` does not count RPF-failed packets for a group with no entry; use `show ip mfib count` (Q4).
- alpine's kernel follows the router's IGMP version only after about 4 minutes (older-version-querier timer): after `ip igmp version 3` wait ~4 min or wipe PC2 before the v3 capture.
- Do not use `clear ip mroute *` mid-run: the stream stalls about 60 s or more. Use a new group.
- The `debug ip pim` and `debug ip igmp` lines quoted below were taken on an idle bench; the lab's handed-over habit is no unconditioned debug, so on a live bench limit them to the group (`debug ip igmp 239.1.1.x`).
- The IGMP compatibility timer (about 4 min) and the `clear ip mroute *` stall are also stated in LAB.md's primer, so the student meets them before the capture.

## Intentional Faults

None (F lab).

## Diagnosis / Methodology

Not applicable. Method for the evidence: viewer first (creates (*,G) on R4), then the encoder; read `show ip mroute 239.1.1.x` on R1-R4 within the first seconds and again after 60 s; capture the R1-R2 link from CML (REST packet capture) for the register exchange; capture R4 e0/2 (or tcpdump on PC2) for IGMP.

## Solution Configuration

All four routers (R2 is the RP, no RP-side config beyond this; R2 and R3 have no LAN, so no LAN interface):

```
ip multicast-routing
ip access-list standard MC
 permit 239.1.0.0 0.0.255.255
ip pim rp-address 10.255.0.2 MC
interface Loopback0
 ip pim sparse-mode
interface Ethernet0/0
 ip pim sparse-mode
interface Ethernet0/1
 ip pim sparse-mode
! R1 and R4 only:
interface Ethernet0/2
 ip pim sparse-mode
```

Requirement R3, on router R4: `ip pim spt-threshold infinity` (global), later removed with `no ip pim spt-threshold infinity`. R4 IGMP: `interface Ethernet0/2` / `ip igmp version 3` (default v2 with PIM enabled). Final state: the spt-threshold line removed, `ip igmp version 3` left on R4 e0/2 (LAB-055 needs it).

## Verification

V1 (R1; R4 shows the same two neighbours without DR):
```
R1# show ip pim neighbor
10.0.12.2   Ethernet0/0   00:00:31/00:01:43 v2    1 / DR S P G
10.0.13.2   Ethernet0/1   00:00:29/00:01:44 v2    1 / DR S P G
R1# show ip pim rp mapping
Acl: MC, Static
    RP: 10.255.0.2 (?)
```
RPF (R5): `show ip rpf 10.0.1.10`: R4 Ethernet0/1 nbr 10.0.34.1 (unicast ospf 1); R3 Ethernet0/0 nbr 10.0.13.1; R2 Ethernet0/0 nbr 10.0.12.1. `show ip rpf 10.255.0.2`: R4 Ethernet0/0 nbr 10.0.24.1; R3 Ethernet0/1 nbr 10.0.34.2; R1 Ethernet0/0 nbr 10.0.12.2. R4 reaches the source over the cheap path (R3) but the RP over R2: that mismatch is why the shared and source trees differ.

V2 (viewer on PC2 for 239.1.1.1, no source):
```
R4# show ip mroute 239.1.1.1
(*, 239.1.1.1), 00:00:02/00:02:58, RP 10.255.0.2, flags: SJC
  Incoming interface: Ethernet0/0, RPF nbr 10.0.24.1
  Outgoing interface list:
    Ethernet0/2, Forward/Sparse, 00:00:02/00:02:58
R2# show ip mroute 239.1.1.1
(*, 239.1.1.1), 00:00:02/00:03:27, RP 10.255.0.2, flags: S
  Incoming interface: Null, RPF nbr 0.0.0.0
  Outgoing interface list:
    Ethernet0/1, Forward/Sparse
R1# show ip mroute 239.1.1.1
Group 239.1.1.1 not found       (R3 likewise)
```

V3 (source running 15 s; the (*,G) timers show `stopped` once an (S,G) exists):
```
R1: (*, 239.1.1.1) flags: SPF  iif Ethernet0/0 (RPF 10.0.12.2)  olist Null
    (10.0.1.10, 239.1.1.1) flags: FT  iif Ethernet0/2  olist Ethernet0/1
R2: (*, 239.1.1.1) flags: S  iif Null  olist Ethernet0/1
    (10.0.1.10, 239.1.1.1) flags: PT  iif Ethernet0/0 (RPF 10.0.12.1)  olist Null
R3: (*, 239.1.1.1) flags: SP  iif Ethernet0/1   (10.0.1.10, 239.1.1.1) flags: T  iif Ethernet0/0  olist Ethernet0/1
R4: (*, 239.1.1.1) flags: SJC iif Ethernet0/0 (RPF 10.0.24.1)  olist Ethernet0/2
    (10.0.1.10, 239.1.1.1) flags: JT  iif Ethernet0/1 (RPF 10.0.34.1)  olist Ethernet0/2
R4# show ip mroute count | begin 239.1.1.1
Group: 239.1.1.1, Source count: 1, Packets forwarded: 422, Packets received: 422
  RP-tree: Forwarding: 0/0/0/0, Other: 0/0/0
  Source: 10.0.1.10/32, Forwarding: 422/24/1344/260, Other: 422/0/0
PC2 viewer: 0/124 (0%), 0/121 (0%), 0/122 (0%) per 5 s (257 kb/s)
```
The shared-tree packet count on R4 is 0 because the switchover happens within the first second (cold start). Over a 60 s run 0 % loss in every interval (several runs, 0/122 per interval).

V4 (REST capture on R1 e0/0, 40 s after start, group 239.1.1.1): `PIM Register 10.0.12.1>10.255.0.2` x4 at t=64.3-64.4 s; `PIM Register-Stop 10.255.0.2>10.0.12.1` x1 at 64.4 s; no Register in the remaining ~60 s; native `UDP 10.0.1.10>239.1.1.1 ttl 15` x2 at 64.3 s (the shared-tree packets before R2 pruned); Join/Prune x2 from 10.0.12.2 (R2 joining (S,G) towards R1). Registration lasted about 0.1 s. R2 `debug ip pim`: `Received v2 Register`, `Received v2 Join/Prune on Ethernet0/1 from 10.0.24.2`, `Prune-list: (10.0.1.10/32, 239.1.1.1) RPT-bit set`, `Send v2 Register-Stop to 10.0.12.1 for 10.0.1.10, group 239.1.1.1`, then every ~60 s `Building Periodic (*,G) Join / (S,G,RP-bit) Prune message`.

V5 (R4 `ip pim spt-threshold infinity`, fresh group 239.1.1.3): R4 has `(*,239.1.1.3)` flags `SC` only, no (S,G); `RP-tree: Forwarding: 1006/24/1344/260`; R2 (S,G) flags `T`, oif Ethernet0/1, forwarding 24 pps; R1 (S,G) oif Ethernet0/0; R3 has no entry (path R1-R2-R4 cost 60 against 20 over R3). After `no ip pim spt-threshold infinity`: R4 (S,G) `JT` appears (age 1 s) within 9 s of the command (poll including CLI overhead).

SPT switchover: three cold-start runs on groups 239.1.1.9/.10/.11: R4 (S,G) flags `JT` within 1 s of the sender starting in all three (`--until` 1 s polls, entry age 0). A first look (1-3 s after the start) showed R4 (*,G) SJC iif e0/0 and (S,G) 1 s old iif e0/1. Documented: 1-3 s.

V6 (IGMP on R4 e0/2):
- v2 (default), capture: `IGMP v2 report 10.0.4.10>239.1.1.4` at t=17.1; `v2 leave 10.0.4.10>224.0.0.2` at 21.1; router `IGMP query 10.0.4.1>239.1.1.4` x2 (group-specific, 1 s apart). `debug ip igmp`: `Received v2 Report`, `Received Leave`, `Lower expiration timer to 2000 msec`, `Send v2 Query ... for group`, `Switching to INCLUDE mode` ~2 s after the leave. `show ip igmp groups 239.1.1.4 detail`: `Group mode: EXCLUDE`, source list empty.
- v3 (`ip igmp version 3`, PC2 wiped for a fresh kernel), reports to 224.0.0.22: `TO_EX:239.1.1.4/0src` (join, t=16.6), `TO_IN:239.1.1.4/0src` (leave, 22.6); source-specific join (`iperf -s -u -B 239.1.1.5 -H 10.0.1.10`): `ALLOW:239.1.1.5/1src` (17.8), leave `BLOCK:239.1.1.5/1src` (21.8). The router sends a group-specific v3 query and `Send v3 Source Query` (group+source). `show ip igmp groups 239.1.1.5 detail`: `Group mode: INCLUDE` with the source list. `Current IGMP router version is 3`.

Q4 evidence: spoofed source (`sudo ip addr add 10.0.4.77/24 dev eth0` on PC1, `iperf -B 10.0.4.77 -c 239.1.1.7 ...`): R1's RPF for 10.0.4.77 is Ethernet0/1 but the packets arrive on Ethernet0/2. `show ip mfib count` on R1, wildcard line `Group: 239.1.0.0/16 ... Other: 1190/1190/0` rising to `1532/1532/0` at 24 pps: all counted as RPF-failed ("Other"), no (S,G) entry created. `show ip mroute count` shows nothing for the group because the packets are dropped before any entry exists for them, so there is no entry whose counters could rise; the platform's mfib wildcard "Other" counter is the only place they appear. Requirement R7 in LAB.md asks for this test (a secondary source address outside the source LAN).

V8: summary of the capture (use `tcpdump -nr` piped to `awk`/`sort | uniq -c`). Registration capture counts above come from such a summary.

## Failure / Recovery Behaviour

Method: cable pull = `shutdown` on both R3 Ethernet0/1 and R4 Ethernet0/1; group 239.1.1.1, viewer `-i 1`, steady state confirmed (R4 (S,G) iif Ethernet0/1) before each run. Clock: a scripted config block plus a CLI poll.

| Scenario (trigger -> end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| Cable pull R3-R4 (shutdown both) -> R4 (S,G) incoming interface = Ethernet0/0 (via R2) | 2 s, 2 s, 2 s | 1-4 s | measured (poll granularity ~1 s); the down interface triggers OSPF and PIM at once |
| Same pull: datagrams lost at the viewer (24 pps) | 3, 2, 3 datagrams | up to 1 s of stream (viewer resolution 1 s) | measured |
| Restore (no shutdown both) -> R4 (S,G) iif back to Ethernet0/1 | 18 s, 18 s, 18 s (an earlier set: 14 s x3) | 10-20 s | measured; includes OSPF adjacency bring-up and the neighbour hold |
| Same restore: viewer loss | 0, 0, 0 | no loss | measured (make-before-break: the old path carries the stream until the new RPF is ready) |

Failover is fast because the shutdown is local on R4: OSPF removes the route at once and the RPF check switches the join to R2 (shared-tree path already known). A silent failure (link stop) would instead wait for the PIM neighbour/OSPF dead timers.

## Answers to Analysis Questions

- **Q1** The viewer's IGMP report makes R4 (the DR/last-hop router on the receiver LAN) create (*,G) and join towards the RP (R2) via the interface with the best route to the RP (Ethernet0/0). The encoder's first packets make R1 (first-hop) create (S,G) when the packet arrives on the connected source LAN (flag F); R1 registers it to the RP, and later R1 receives a join for the source tree.
- **Q2** R2 receives the Register, finds receivers in its (*,G) and joins the (S,G) towards R1 (native packets arrive); once native multicast comes in over the source tree it sends Register-Stop to stop encapsulation (about 0.1 s after the first register in the capture). Once R4 has switched to the source tree, R4 sends an (S,G) RPT-bit prune to R2; R2 then prunes (S,G) towards R1 (its (S,G) entry is `PT` with an empty OIL).
- **Q3** The shared path R1-R2-R4 costs 60, the source tree R1-R3-R4 only 20; with the default threshold (0) the last-hop router joins the source tree on the first packet (flag `J`/`T`). Cost/benefit for the RP: the RP no longer forwards the stream (its (S,G) is `PT`, RP-tree count 0) and no longer carries the load; with `spt-threshold infinity` the stream stays on the shared tree and R2 forwards 24 pps (R2 (S,G) `T` oif Ethernet0/1; R4 `RP-tree: Forwarding: 1006/24/1344/260`).
- **Q4** Packets that arrive on an interface that is not the RPF interface towards their source are dropped, and no (S,G) entry is created for them (loop prevention). On iol-xe they are visible only in `show ip mfib count` (wildcard line, "Other", rising 1190 -> 1532).
- **Q5** v2: report (sent to the group address), leave to 224.0.0.2, router answers with group-specific queries. v3: reports to 224.0.0.22 with group records (TO_EX/TO_IN for any-source, ALLOW/BLOCK with a source list), no suppression, and the router tracks include/exclude mode and sources. v3 lets a host name the source, which is what SSM (S,G) joins need without any RP; v2 cannot express it.
- **Q6** (measured: `-T 3` delivers only the first 3 datagrams, the register/shared-tree start, then 0 in steady state; `-T 4` 0 % loss) the packet crosses three routers (R1, R3, R4), each of which decrements the TTL and drops a packet arriving with TTL 1: the encoder needs TTL >= 4 (the bench streams use 16). With `-T 1` R1 receives TTL 1 and discards the packet instead of forwarding it. The capture shows `ttl 15` on R1-R2 for `-T 16`.
- **Q7** Register and the shared-tree path are only used until the source-tree join reaches R1; R4 joins (S,G) towards R1 over R3 before it prunes the source off the shared tree (make-before-break), so the viewer sees 0 % loss, and the RPT-bit prune only stops the RP forwarding a duplicate.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a) |
