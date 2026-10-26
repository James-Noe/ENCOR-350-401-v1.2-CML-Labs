# LAB-007 — Solution

## Summary

Foundation lab (F · G3 · 60 min) for **X-L2guards** (BPDU filter, loop guard, UDLD, errdisable recovery), practising **3.1.c**. It starts from LAB-006's Rapid PVST+ design after R2–R4 (SW1 root for VLANs 10/99, SW2 for VLAN 20, host ports PortFast + BPDU guard, root guard on SW1/SW2 downlinks). Order: BPDU guard (known) → BPDU filter → loop guard. The student:

- enables the global PortFast BPDU filter on the access switches and sees that it only touches edge ports (R1);
- enables loop guard on the access uplinks (R2) and proves it contains a BPDU-stopping failure created with interface-level BPDU filter (R3);
- runs UDLD aggressive on SW3's uplinks (R4) and errdisable recovery for bpduguard/udld at 30 s (R5);
- observes a one-sided shutdown: loop guard reacts in ~3 s, UDLD aggressive err-disables the silent port after ~45 s, errdisable recovery re-enables it 30 s later (V6).

Toolkit recurrence (4.1): V3/V6 (continuous ping), V3/V5/V6 (log lines with timestamps).

No intentional faults (F lab). Rapid PVST+ is used; the MST variant was not tried.

## Solution Configuration

Tested in CML. Configuration mode.

**R1** (SW3, SW4)
```
spanning-tree portfast bpdufilter default
```

**R2** (SW3, SW4)
```
interface range Ethernet0/0 - 1
 spanning-tree guard loop
```

**R3** (test; SW2), only after `show spanning-tree interface Ethernet0/1 detail` on SW3 shows `Loop guard is enabled on the port`
```
interface Ethernet0/1
 spanning-tree bpdufilter enable
! ... observe ...
interface Ethernet0/1
 no spanning-tree bpdufilter enable
```

**R4**
```
! SW1 and SW2
interface Ethernet0/1
 udld port aggressive
! SW3
interface range Ethernet0/0 - 1
 udld port aggressive
```

**R5** (all four switches)
```
errdisable recovery cause bpduguard
errdisable recovery cause udld
errdisable recovery interval 30
```
Proof on SW4:
```
interface Ethernet0/1
 spanning-tree bpduguard enable
! ... watch two or more recovery cycles ...
interface Ethernet0/1
 no spanning-tree bpduguard enable
```

## Verification

Captured in CML (MACs in that build: SW1 aabb.cc00.7400, SW2 .7500; they differ per import).

**Start state.** SW3 `show spanning-tree root`: VLAN10 `24586 aabb.cc00.7400 100 … Et0/0`, VLAN20 `24596 aabb.cc00.7500 … Et0/1`, VLAN99 `24675 … Et0/0`. SW3 and SW4 blocked ports: VLAN10 Et0/1, VLAN20 Et0/0, VLAN99 Et0/1. Filter/loop-guard defaults disabled; PC1→PC2 4/4.

**R1.** SW4 `show spanning-tree summary` → `Portfast BPDU Filter Default is enabled`. SW4 `show spanning-tree interface Ethernet1/0 detail`:
```
   The port is in the portfast mode
   Bpdu guard is enabled
   Bpdu filter is enabled by default
   BPDU: sent 57, received 0
```
The sent counter was still 57 at the next check (the edge port stopped sending BPDUs). The uplink Ethernet0/1 has no filter line and keeps exchanging BPDUs: on an access uplink the **received** counter rises while sent stays flat (`BPDU: sent 12, received 75`; validation: sent 12, received 87 → 128). SW3 Et1/0: `Bpdu filter is enabled by default`, `BPDU: sent 94, received 0`. Explanation expected from the student: the global filter applies only to ports that are operationally PortFast ("by default"); such a port sends a few BPDUs at link-up, then stops. If it receives a BPDU, it stops the default filtering and processes BPDUs normally (normal spanning tree); on this platform it keeps its `portfast mode` / Edge label (here BPDU guard, also configured on the port, would err-disable it first). The behaviour on BPDU receipt was captured on SW4 Et0/1 (`spanning-tree portfast trunk`, no port bounce).

**R2.** SW3 `show spanning-tree interface Ethernet0/1 detail`:
```
 Port 2 (Ethernet0/1) of VLAN0010 is alternate blocking
   Loop guard is enabled on the port
 Port 2 (Ethernet0/1) of VLAN0020 is root forwarding
   Loop guard is enabled on the port
 Port 2 (Ethernet0/1) of VLAN0099 is alternate blocking
   Loop guard is enabled on the port
```

**R3.** After the filter on SW2 Et0/1, SW3:
```
%SPANTREE-2-LOOPGUARD_BLOCK: Loop guard blocking port Ethernet0/1 on VLAN0010.

Name                 Interface                      Inconsistency
VLAN0010             Ethernet0/1                    Loop Inconsistent
VLAN0020             Ethernet0/1                    Loop Inconsistent
VLAN0099             Ethernet0/1                    Loop Inconsistent

VLAN0010  Et0/0  Root FWD 100  128.1  P2p
          Et0/1  Desg BKN*100  128.2  P2p *LOOP_Inc
VLAN0020  Et0/0  Root FWD 100  128.1  P2p
          Et0/1  Root BKN*100  128.2  P2p *LOOP_Inc
```

Which VLANs get a `LOOPGUARD_BLOCK` log line varies between runs (the validation run logged VLAN0020 and VLAN0099); expect one or more lines. `show spanning-tree inconsistentports` is the authoritative evidence (3 entries).
In the run captured above only the VLAN0010 line appeared in the log buffer although three VLANs were blocked (in the validation run it was VLAN0020 and VLAN0099), which is why the inconsistent-ports table, not the log, is the evidence to quote. VLAN 20, whose root port was Et0/1, failed over to Et0/0 (via SW1). SW2 Et0/1 for every VLAN: `designated forwarding`, `Bpdu filter is enabled`, sent counter frozen: SW2 forwards on its side, so only SW3's loop guard stops a loop. PC1 continuous ping across the test: `400 packets transmitted, 400 packets received, 0% packet loss`. After removing the filter: `%SPANTREE-2-LOOPGUARD_UNBLOCK: Loop guard unblocking port Ethernet0/1 on VLAN0010.`, inconsistent 0, blocked ports back to the start pattern.

**R4.** SW3 right after configuration listed both neighbours as `Unknown` (`Total number of bidirectional entries displayed: 0`), about a minute later:
```
Port           Device Name     Device ID    Port ID         Neighbor State
Et0/0          2039924         1            Et0/1           Bidirectional
Et0/1          2039925         1            Et0/1           Bidirectional
Total number of bidirectional entries displayed: 2
```
`show udld Ethernet0/1`: `Port enable operational state: Enabled / in aggressive mode`, `Current bidirectional state: Bidirectional`, `TLV CDP Device name: SW2.veridian.example`. SW1 `show udld neighbors`: `Et0/1  2039922  1  Et0/0  Bidirectional`.

**R5.** SW4 `show errdisable recovery`: `bpduguard Enabled`, `udld Enabled`, `Timer interval: 30 seconds`, and while disabled `Et0/1  bpduguard  21` (seconds to next attempt). Log:
```
21:52:06.547 %SPANTREE-2-BLOCK_BPDUGUARD: Received BPDU from bridge aabb.cc00.7500 on port Et0/1 with BPDU Guard enabled. Disabling port.
21:52:06.547 %PM-4-ERR_DISABLE: bpduguard error detected on Et0/1, putting Et0/1 in err-disable state
21:52:36.536 %PM-4-ERR_RECOVER: Attempting to recover from bpduguard err-disable state on Et0/1
21:52:36.554 %SPANTREE-2-BLOCK_BPDUGUARD: Received BPDU from bridge aabb.cc00.7500 on port Et0/1 with BPDU Guard enabled. Disabling port.
21:52:36.554 %PM-4-ERR_DISABLE: bpduguard error detected on Et0/1, putting Et0/1 in err-disable state
21:53:06.552 %PM-4-ERR_RECOVER: Attempting to recover from bpduguard err-disable state on Et0/1
21:53:06.561 %SPANTREE-2-BLOCK_BPDUGUARD: ... Disabling port.
   (no spanning-tree bpduguard enable)
21:53:36.560 %PM-4-ERR_RECOVER: Attempting to recover from bpduguard err-disable state on Et0/1
21:53:38.561 %LINK-3-UPDOWN: Interface Ethernet0/1, changed state to up
```
Afterwards `show interfaces status err-disabled` is empty and the blocked ports are back to the start pattern.

**End state (V7).** SW1 running config: `errdisable recovery cause udld`, `errdisable recovery cause bpduguard`, `errdisable recovery interval 30`, ` udld port aggressive`, root guard on Et0/1–0/2. Inconsistent ports 0, nothing err-disabled, PC1→PC2 `4 packets transmitted, 4 packets received, 0% packet loss`.

## Failure / Recovery Behaviour

**R3** is the failure test (above): loop guard blocked SW3 Et0/1 for all three VLANs; no loop, no ping loss; automatic release when BPDUs returned.

**V6 — one-sided shutdown of SW1 Ethernet0/1** (SW3 Et0/0 stays up/up): with a ping already running, PC1 loses about 4–6 s of pings right after the shutdown (validation: 24 pings at 0.2 s) while BPDUs age out; after that there is no further loss.
```
SW1 21:55:35.501 %LINK-5-CHANGED: Interface Ethernet0/1, changed state to administratively down
SW3 21:55:38.201 %SPANTREE-2-LOOPGUARD_BLOCK: Loop guard blocking port Ethernet0/0 on VLAN0010.
SW3 21:56:20.398 %UDLD-4-UDLD_PORT_DISABLED: UDLD disabled interface Et0/0, aggressive mode failure detected
SW3 21:56:20.398 %PM-4-ERR_DISABLE: udld error detected on Et0/0, putting Et0/0 in err-disable state
SW3 21:56:50.390 %PM-4-ERR_RECOVER: Attempting to recover from udld err-disable state on Et0/0
SW3 21:56:52.391 %LINK-3-UPDOWN: Interface Ethernet0/0, changed state to up
SW1 21:57:16.445 %LINK-3-UPDOWN: Interface Ethernet0/1, changed state to up   (no shutdown)
```
While disabled: `Et0/0  SW1 Ethernet err-disabled udld`, `Current bidirectional state: Unknown`, `Current operational state: Disabled port`. The root port, starved of BPDUs, went loop-inconsistent (~3 s) and the alternate took over; PC1→PC2 4/4 during the err-disable and `500 packets transmitted, 500 packets received, 0% packet loss` across recovery and restore. Afterwards: both UDLD neighbours bidirectional, blocked ports normal, 0 inconsistent. With the far end down longer than one UDLD detection cycle after the recovery, the port would be err-disabled again (derived from the R5 behaviour; not observed).

## Answers to Analysis Questions

**Q1.** An interface-level BPDU filter stops the port both sending and processing BPDUs, so spanning tree on that switch treats the link as if no bridge were there and makes the port designated forwarding (R3: SW2 Et0/1 `designated forwarding` for all VLANs), and the neighbour stops hearing BPDUs. Without loop guard, SW3 Et0/1 (VLAN 10 alternate) would have aged out SW2's information after three missed hellos (~6 s), become designated and forwarding. Then SW1 Et0/0 ↔ SW2 Et0/0, SW2 Et0/1 → SW3 Et0/1, SW3 Et0/0 → SW1 Et0/1 would all forward for VLAN 10: a bridging loop through SW1–SW2–SW3 with broadcasts circulating and MAC tables flapping (derived, deliberately not reproduced: a real loop would destabilise the lab). With loop guard the port went `*LOOP_Inc` instead and stayed blocked.

**Q2.** UDLD detects at layer 1/2 that a link carries traffic in one direction only (for example a failed fibre strand or transceiver, or miswired fibre pairs), even on ports that spanning tree does not use, and in aggressive mode err-disables a port whose neighbour goes silent (V6: `aggressive mode failure detected` after ~45 s). Loop guard only protects spanning-tree root/alternate ports, and only against the loss of BPDUs, whatever the cause, including causes UDLD cannot see: a software fault or BPDU filter on the far switch (R3, where the link was physically fine and UDLD stayed bidirectional) or a congested control plane dropping BPDUs. They complement each other: loop guard reacts per VLAN within about 6 s (3 s observed in V6) and recovers by itself; UDLD takes the whole port down. CML cannot cut one direction of a link, so V6 (a one-sided shutdown) is the closest observation.

**Q3.** Auto-recovery re-enables the port blindly. If the cause is still there, the port flaps: R5's test port was re-enabled every 30 s and disabled again within 20 ms each time. On a BPDU-guard port that means a rogue switch gets a short forwarding window every cycle, risking a loop or a moment of bad topology; on a UDLD port with a genuinely one-way fibre it periodically reopens a link that can cause a loop. Recovery also hides the event from people who would otherwise have to investigate. It is a bad idea where the cause needs a human (a rogue switch, a bad cable), on critical uplinks, or with short intervals; it is reasonable for transient causes on user edge ports, with a long enough interval and logging/monitoring of `ERR_RECOVER`.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), ioll2-xe (IOS XE 17.16.1a) |
