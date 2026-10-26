# HQ H0 stage baseline

Built and proven in CML by LAB-009.

**Profile:** DIST1/2 + ACC1/2, no CORE (6 nodes): HQ-DIST1, HQ-DIST2 (distribution/collapsed core), HQ-ACC1, HQ-ACC2 (access), HQ-PC1, HQ-PC2 (end hosts). ACC3/PC3 are added in a later stage. This 6-node baseline is the **full without CORE1/2** profile, not "lite".

## Topology

```
                 HQ-DIST1 ══════ HQ-DIST2      (Po1: e0/0+e0/1 LACP, nonegotiate trunk)
                    |    \      /    |
                 e0/2      \  /      e0/3
                    |    e0/2 \ e0/3   |
                 HQ-ACC1          HQ-ACC2
                (e0/0,e0/1)      (e0/0,e0/1)
                    |                 |
                  e1/0 (VLAN10)     e1/0 (VLAN20)
                    |                 |
                 HQ-PC1            HQ-PC2
```

Cabling and addressing are in LAB-009's LAB.md. Node types: HQ-DIST1/2 and HQ-ACC1/2 `ioll2-xe`; HQ-PC1/2 `alpine`.

## Content

- VLANs 10 USERS, 20 OPS, 99 MGMT, 999 NATIVE; `vtp mode transparent` (no VTP server/client).
- All 6 inter-switch links: static nonegotiate 802.1q trunks, native 999, allowed 10/20/99.
- HQ-DIST1–HQ-DIST2: one LACP port-channel (Po1, members e0/0+e0/1).
- Rapid PVST+: HQ-DIST1 root (priority 24576) for VLANs 10/20/99; HQ-DIST2 secondary (priority 28672). This headroom (not the lowest valid priority, 4096) is deliberate: it leaves room below HQ-DIST1/2 for a later rogue-root fault (e.g. LAB-010 F4) to actually win an election.
- HQ-DIST1 is the only L3 gateway: `ip routing`, Vlan10/Vlan20/Vlan99 SVIs. HQ-DIST2/ACC1/ACC2 do not route; HQ-DIST2 reaches other subnets via a static default route to HQ-DIST1, HQ-ACC1/ACC2 via `ip default-gateway` (see build note below).
- Host ports (ACC e1/0): access mode, PortFast, BPDU guard.
- No root guard, loop guard or UDLD yet. Root guard on the DIST downlinks and loop guard on the access uplinks arrive in H1 (LAB-012).

## Build notes (from LAB-009)

1. **`ip default-gateway` needs `no ip routing` first.** ioll2-xe has a hidden default of `ip routing` **on**, even on a switch with no other L3 config. With `ip routing` on, `ip default-gateway` is silently ignored. HQ-ACC1/ACC2 day-0 must include `no ip routing` before `ip default-gateway 10.10.99.11`, or the switch cannot originate traffic (pings, SSH) to anything outside its directly connected 10.10.99.0/24.
2. **Day-0 order: `interface Port-channel1` comes before its member interfaces** in HQ-DIST1.cfg/HQ-DIST2.cfg. With Port-channel1 after the members, a cold boot brings Po1 up suspended on both ends (`Po1(SD) LACP Et0/0(s) Et0/1(s)`, `%ETC-5-CANNOT_BUNDLE2: ... dtp nonegotiate of Et0/0 is 1, Po1 id 0`, then `%ETC-5-L3DONTBNDL2`): the members are bundled into a Po1 that does not yet have `switchport nonegotiate`. With Port-channel1 first, both ends come up `Po1(SU) LACP Et0/0(P) Et0/1(P)` on consecutive cold boots with no bounce (CML cold-boot feature test). Keep this order in every lab or stage derived from H0. If a bundle is ever found suspended this way (for example after configuring it live in the wrong order), bounce both members on both switches: `interface range Ethernet0/0-1` / `shutdown` / `no shutdown`.
3. Rapid-PVST convergence after a topology change (e.g. an uplink shutdown) is fast on these p2p ports (root-port reselection observed within one polling round-trip, well under the 20 s max-age); do not expect the classic 802.1D 30–50 s numbers.
4. A node **stop/start (power cycle)** reloads the switch's startup-config, not its last running-config — VLAN database entries survive independently (`vlan.dat`), but trunk/channel/SVI config does not unless it was part of the startup config (`write memory` or, as here, baked into the day-0 file). This is normal IOS/IOL behaviour, not a CML defect, but matters when scripting failure tests: only the config in these `.cfg` files is guaranteed to survive a HQ-DIST1/2 power-cycle.

## Files

`HQ-DIST1.cfg`, `HQ-DIST2.cfg`, `HQ-ACC1.cfg`, `HQ-ACC2.cfg`, `HQ-PC1.cfg`, `HQ-PC2.cfg` — one startup config per device, the full H0 solved state (not a lab's fault-injected start state). A lab that starts from H0 loads these as day-0 and applies its own changes/faults on top; LAB-009 itself ships a different, unconfigured day-0 (see its own LAB-009.yaml) since 009 is the lab where the student builds this baseline from scratch.
