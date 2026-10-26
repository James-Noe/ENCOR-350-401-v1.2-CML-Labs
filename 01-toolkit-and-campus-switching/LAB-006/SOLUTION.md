# LAB-006 — Solution

## Summary

Implementation lab (I · G3 · 90 min) for blueprint **3.1.c** (RSTP/MST, root placement, PortFast, BPDU guard, root guard), reinforcing 3.1.a/3.1.b. On the FND square (SW1/SW2 distribution role, SW3/SW4 dual-homed access, PC1/PC2 in VLAN 10) the student:

- reads the MAC-elected default tree (R1) — in every build so far an **access switch** (SW3) was root;
- engineers Rapid PVST+ roots per VLAN (SW1: 10, 99; SW2: 20) and predicts the per-VLAN blocked uplinks (R2–R3);
- adds PortFast + BPDU guard on host ports and root guard on distribution downlinks, and proves both guards (R4–R6);
- migrates to an MST region `VERIDIAN` rev 1 with instance 1 (10, 99) and 2 (20), with the IST root placed at SW1 (R7);
- measures failover (0 loss with local link-down detection, about 4–6 s, i.e. 20–30 pings at 0.2 s, when BPDUs must age out) and observes an MST region boundary (V8–V9).

Toolkit recurrence (4.1): V5/V6 (log lines), V8 (continuous ping with loss counted).

No intentional faults (I lab).

## Solution Configuration

Tested in CML. Commands in configuration mode.

**R2 — Rapid PVST+ roots**
```
! SW1
spanning-tree mode rapid-pvst
spanning-tree vlan 10,99 root primary
spanning-tree vlan 20 root secondary
! SW2
spanning-tree mode rapid-pvst
spanning-tree vlan 20 root primary
spanning-tree vlan 10,99 root secondary
! SW3, SW4
spanning-tree mode rapid-pvst
```
Stored as `spanning-tree vlan 10,99 priority 24576` / `vlan 20 priority 28672` (SW1) and `vlan 10,99 priority 28672` / `vlan 20 priority 24576` (SW2). Each mode change prints `Warning: Changing STP mode can disrupt the traffic and make system unstable`.

**R4 — edge and downlink protection**
```
! SW3 and SW4
interface Ethernet1/0
 spanning-tree portfast
 spanning-tree bpduguard enable
! SW1 and SW2
interface range Ethernet0/1 - 2
 spanning-tree guard root
```
(`spanning-tree portfast bpduguard default` globally is an equally valid answer for BPDU guard.)

**R5 — root guard test**
```
! SW4
spanning-tree vlan 10 priority 0
! ... observe ...
no spanning-tree vlan 10 priority 0
```

**R6 — BPDU guard test**
```
! SW4
interface Ethernet0/1
 spanning-tree bpduguard enable
! ... observe err-disable ...
interface Ethernet0/1
 no spanning-tree bpduguard enable
 shutdown
 no shutdown
```

**R7 — MST migration** (region first on every switch, then the mode, SW1 → SW2 → SW3 → SW4)
```
! all four switches
spanning-tree mst configuration
 name VERIDIAN
 revision 1
 instance 1 vlan 10,99
 instance 2 vlan 20
 exit
! SW1
spanning-tree mst 0 root primary
spanning-tree mst 1 root primary
spanning-tree mst 2 root secondary
! SW2
spanning-tree mst 0 root secondary
spanning-tree mst 2 root primary
spanning-tree mst 1 root secondary
! all four switches, one at a time
spanning-tree mode mst
```
Stored on SW1 as `spanning-tree mst 0-1 priority 24576`, `spanning-tree mst 2 priority 28672`; on SW2 `mst 0-1 priority 28672`, `mst 2 priority 24576`. The Rapid PVST+ `spanning-tree vlan … priority` lines stay in the configuration but are inactive in MST mode (students may remove them).

**Build note (why `mst 0` is in the solution).** The build first set only MSTI 1/2 roots. The IST/CIST root was then MAC-elected, and the lowest MAC was SW3's: SW3 and SW4 sent superior CIST BPDUs up, and root guard on SW1/SW2 blocked the downlinks **for all instances** (6 root-inconsistent entries on SW1, PC1→PC2 100 % loss). Adding `spanning-tree mst 0 root primary` on SW1 (secondary on SW2) cleared it at once. See Q5.

## Verification

Captured in CML (bridge MACs in that build: SW1 aabb.cc00.6800, SW2 .6900, SW3 .6600, SW4 .6700; MACs differ per import).

**R1 — default tree (student start state).** Root for all VLANs = SW3 (lowest MAC). SW1: Et0/0 Desg, Et0/1 Root, Et0/2 Desg. SW2 (`show spanning-tree blockedports`):
```
VLAN0010             Et0/0
VLAN0020             Et0/0
VLAN0099             Et0/0
```
SW4: Et0/0 Root FWD, Et0/1 Altn BLK for all VLANs. Why: SW3 wins on MAC (all priorities 32768 + VLAN). SW1 and SW2 each reach SW3 at cost 100 directly. On SW1–SW2, both advertise cost 100, so the lower sender bridge ID (SW1) wins designated and SW2 Et0/0 blocks. SW4 reaches the root at cost 200 via SW1 or SW2; equal cost, so the lower sender bridge ID (SW1) wins, SW4 Et0/1 (to SW2) is alternate. In the re-imported lab SW3 was root again (MAC aabb.cc00.6e00); students must derive their own.

**R2/R3 — Rapid PVST+.** SW1 `show spanning-tree bridge`:
```
VLAN0010         24586 (24576,  10) aabb.cc00.6800    2    20   15  rstp
VLAN0020         28692 (28672,  20) aabb.cc00.6800    2    20   15  rstp
VLAN0099         24675 (24576,  99) aabb.cc00.6800    2    20   15  rstp
```
SW3 `show spanning-tree root`:
```
VLAN0010         24586 aabb.cc00.6800       100    2   20  15  Et0/0
VLAN0020         24596 aabb.cc00.6900       100    2   20  15  Et0/1
VLAN0099         24675 aabb.cc00.6800       100    2   20  15  Et0/0
```
Predicted = observed on SW3 **and** SW4 (`show spanning-tree blockedports`):
```
VLAN0010             Et0/1
VLAN0020             Et0/0
VLAN0099             Et0/1
```
SW1 and SW2: no blocked ports. The access switch blocks its uplink to the non-root distribution switch, because that switch (backup-root priority) is designated on the shared segment.

**R4.** SW3/SW4 `Et1/0  Desg FWD 100  128.5  P2p Edge`; `show spanning-tree interface Ethernet1/0 portfast` → `VLAN0010  enabled`. SW1/SW2 log `%SPANTREE-2-ROOTGUARD_CONFIG_CHANGE: Root guard enabled on port Ethernet0/1.` (and 0/2). `show spanning-tree inconsistentports` → 0.

**R5 — root guard.** SW1 and SW2 log:
```
%SPANTREE-2-ROOTGUARD_BLOCK: Received a superior STP BPDU from bridge aabb.cc00.6700. Root guard blocking port Ethernet0/2 on VLAN0010.
```
SW1 `show spanning-tree inconsistentports` → `VLAN0010  Ethernet0/2  Root Inconsistent`; `Et0/2  Desg BKN*100  128.3  P2p *ROOT_Inc`. SW1 stays root (24586). SW4 reports `Root ID Priority 10 / This bridge is the root` and is cut off for VLAN 10: PC1→PC2 `3 packets transmitted, 0 packets received, 100% packet loss`. After the revert: `%SPANTREE-2-ROOTGUARD_UNBLOCK: Root guard unblocking port Ethernet0/2 on VLAN0010.`, 0 inconsistent ports, no manual action.

**R6 — BPDU guard.** SW4:
```
%SPANTREE-2-BLOCK_BPDUGUARD: Received BPDU from bridge aabb.cc00.6900 on port Et0/1 with BPDU Guard enabled. Disabling port.
%PM-4-ERR_DISABLE: bpduguard error detected on Et0/1, putting Et0/1 in err-disable state
```
`show interfaces status err-disabled` → `Et0/1  SW2 Ethernet err-disabled bpduguard`. VLAN 20 on SW4 moved to root port Et0/0 (via SW1). After removing the guard and `shutdown` / `no shutdown`: err-disabled list empty, Et0/1 up/up, blocked ports back to VLAN10 Et0/1, VLAN20 Et0/0, VLAN99 Et0/1.

**R7 — MST.** SW4 `show spanning-tree mst configuration digest`:
```
Name      [VERIDIAN]
Revision  1     Instances configured 3
Digest          0xBA79ED591A4E20323F8F97170985D9FF
```
SW2 `show spanning-tree mst`:
```
##### MST0    vlans mapped:   1-9,11-19,21-98,100-4094
Bridge        address aabb.cc00.6900  priority      28672 (28672 sysid 0)
Root          address aabb.cc00.6800  priority      24576 (24576 sysid 0)
Regional Root address aabb.cc00.6800  priority      24576 (24576 sysid 0)
##### MST1    vlans mapped:   10,99
Root          address aabb.cc00.6800  priority      24577 (24576 sysid 1)
##### MST2    vlans mapped:   20
Root          this switch for MST2
```
SW3 and SW4 `show spanning-tree blockedports`:
```
MST0                 Et0/1
MST1                 Et0/1
MST2                 Et0/0
```
Same pattern as R3 (MST1 = VLAN 10/99, MST2 = VLAN 20); costs now 2000000. Inconsistent ports 0, err-disabled none, PC1→PC2 3/3.

## Failure / Recovery Behaviour

**V8 — SW1–SW3 link failure** (PC1 `sudo ping -i 0.2 10.0.10.102`):

| Test | Result |
|---|---|
| Rapid PVST+, both ends shut (SW3 Et0/0 first, then SW1 Et0/1) | `400 packets transmitted, 400 packets received, 0% packet loss`; SW3 Et0/1 Altn → Root FWD at once |
| Rapid PVST+, restore both ends | `300 … 300 received, 0% packet loss` |
| Rapid PVST+, only SW1 Et0/1 shut | `300 … 273 received, 9% packet loss`, one gap of 27 pings ≈ 5.4 s (validation run: 21 pings ≈ 4.2 s; accept 20–30 pings); SW3 Et0/0 stayed `up, line protocol is up` and became `Desg FWD` toward the dead port |
| MST, both ends shut | `400 … 400 received, 0% packet loss` |
| MST, only SW1 Et0/1 shut | `300 … 273 received, 9% packet loss`, gap 27 pings ≈ 5.4 s (validation run: 24 pings ≈ 4.8 s; accept 20–30 pings). V8's one-ended test is asked in MST; either mode gives the same range |

Rapid PVST+ and MST behave the same (both use RSTP handshakes and alternate ports). When the switch owning the root port sees the link go down, the alternate port takes over instantly. When only the far end is shut (a CML artefact, but also what a failed transceiver or a one-way fault looks like), SW3 must miss three hellos (6 s) before it ages out the root-port information.

**V9 — MST revision 2 on SW4:**
```
##### MST0
Root          address aabb.cc00.6800  priority      24576 (24576 sysid 0)
              port    Et0/0           path cost     2000000
Regional Root this switch
Et0/0                            Root FWD 2000000   128.1    P2p Bound(RSTP)
Et0/1                            Altn BLK 2000000   128.2    P2p Bound(RSTP)
##### MST1
Root          this switch for MST1
Et0/0                            Mstr FWD 2000000   128.1    P2p Bound(RSTP)
Et0/1                            Altn BLK 2000000   128.2    P2p Bound(RSTP)
##### MST2
Root          this switch for MST2
Et0/0                            Mstr FWD 2000000   128.1    P2p Bound(RSTP)
Et0/1                            Altn BLK 2000000   128.2    P2p Bound(RSTP)
```
SW4 is its own region: it is regional root and root of MST1/MST2 locally, and all its instances follow the CIST at the boundary, so VLAN 20 now leaves SW4 via Et0/0 (SW1) instead of Et0/1 (SW2). PC1→PC2 still works; nothing inconsistent. On the distribution side the ports toward SW4 still showed plain `P2p`, and SW1 `show spanning-tree mst interface Ethernet0/2` reported `Boundary : internal`: only SW4 flagged the boundary in this build. Restoring `revision 1` returned SW4 to the region (`Regional Root address aabb.cc00.6800`, MST2 root port Et0/1, `rem hops 19`); unused ports appeared briefly in the MST0 blocked list and cleared within the forward delay.

## Answers to Analysis Questions

**Q1.** The default root is elected on MAC address alone, so any switch can win: here an access switch (SW3). All traffic then follows paths centred on a closet switch with the weakest uplinks, the distribution interlink blocks, and SW4's traffic takes a three-hop detour. Adding a switch with a lower MAC (or replacing one) moves the root and reshuffles every blocked port, a network-wide outage caused by an unrelated change. Deliberate priorities make the root deterministic and put it where the paths converge anyway.

**Q2.** Both give each distribution switch the forwarding role for part of the VLANs, so both uplinks of each access switch carry traffic (VLAN 10/99 via SW1, VLAN 20 via SW2) while every VLAN stays loop-free. Rapid PVST+ does this with one spanning-tree instance per VLAN: configuration is per VLAN, and every VLAN costs its own BPDUs, state and CPU on every trunk, which grows linearly with the number of VLANs (and hits instance limits on real hardware). MST maps many VLANs to a few instances, sending one BPDU per port carrying all instances; the cost is the region configuration, which must be identical (name, revision, VLAN map) on every switch and must be changed everywhere at once when VLANs are added.

**Q3.** A switch with a different revision (or name or VLAN map) computes a different configuration digest and becomes a separate region. Its links to the rest become boundary ports (`Bound(RSTP)`). Across a boundary only the CIST exists: every instance on the boundary port takes the CIST role and state, and the switch is the root of its own MSTIs (V9: `Root this switch for MST1/MST2`, `Regional Root this switch`). SW4 therefore blocked Et0/1 for instance 2 as well, and VLAN 20 went via SW1: the per-instance load sharing was lost without any error or log message, which makes this a classic silent misconfiguration.

**Q4.** BPDU guard belongs on edge (host) ports, where no BPDU should ever arrive: a BPDU means someone connected a switch, so the port is err-disabled. Root guard belongs on the designated ports facing switches that may legitimately send BPDUs but must never become root: here the distribution downlinks. It blocks only while superior BPDUs arrive and recovers by itself. The other way round fails: BPDU guard on a distribution downlink err-disables it as soon as the access switch sends its normal BPDUs (R6 showed this on SW4 Et0/1), and root guard on a host port does nothing useful against a rogue switch that does not claim root.

**Q5.** In MST, root guard acts on the port for every instance, and the decisive election for the port is the CIST's. Setting only the MSTI 1/2 roots leaves the IST root to MAC addresses. In the build, SW3 had the lowest MAC, so SW3 and SW4 sent superior CIST BPDUs to SW1/SW2, whose root guard declared both downlinks root-inconsistent for MST0, MST1 and MST2: six inconsistent entries on SW1, SW3/SW4 isolated, PC1→PC2 100 % loss. Placing `spanning-tree mst 0 root primary` on SW1 (secondary on SW2) makes the distribution layer win the CIST and releases the ports (`ROOTGUARD_UNBLOCK … on MST0`). A classmate whose import gave SW1 or SW2 the lowest MAC would not see the problem, which is exactly why the design must not rely on it.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), ioll2-xe (IOS XE 17.16.1a) |
