# LAB-064 — Solution

## Summary

A/F lab, no faults. The student builds a VLAN-aware Linux bridge (a virtual switch) on a KVM host, compares its forwarding table with the physical switch's, and runs the one experiment that matters for a campus network: a virtual switch that starts sending BPDUs into a hypervisor port. Blueprint mapping: 2.1.a (hypervisor types: CML controller = type 1 KVM host, nodes = VM/container/process), 2.1.b (virtual machine components: vCPU, RAM, disk, virtio NIC), 2.1.c (virtual switching: Linux bridge, tagged uplink, access ports, FDB), 3.1.c (BPDU guard, PortFast on trunk, root election with PVST+).

Design decisions (as built): the ACC1 trunk carries all VLANs (no `allowed vlan` line), so the experiment is observable (see Q7); R5 compares VLAN 1 with VLAN 10 (the root of VLAN 10 does not change, see Q6). Alpine in this image has `ethtool -i` and `lscpu`; only `systemd-detect-virt` is missing.

## Intentional Faults

None. R4/R5 are instructed experiments.

## Diagnosis / Methodology

Not a troubleshooting lab. Method for R4: after `stp_state 1`, all hosts behind MGMT1 (PC1, PC2) lose service within seconds, PC3 (on ACC1) is unaffected. `show interfaces status err-disabled` gives reason `bpduguard`; the log names the sending bridge MAC, which equals br0's MAC (`ip -br link show br0`), identifying the BPDU source as the host's bridge. Method for R5: `show spanning-tree root` for every VLAN, then the port role of e0/0 per VLAN.

## Solution Configuration

R1 values (observed, section 'Verification').

R2, on AUTO-MGMT1 (sudo):

```
ip link add br0 type bridge vlan_filtering 1 stp_state 0
ip link set ens2 master br0
ip link set ens3 master br0
ip link set ens4 master br0
ip link set br0 up
bridge vlan del vid 1 dev ens2
bridge vlan del vid 1 dev ens3
bridge vlan del vid 1 dev ens4
bridge vlan add vid 10 dev ens2
bridge vlan add vid 20 dev ens2
bridge vlan add vid 10 dev ens3 pvid untagged
bridge vlan add vid 20 dev ens4 pvid untagged
```

R4, AUTO-ACC1 `interface Ethernet0/0`: `spanning-tree portfast trunk`, `spanning-tree bpduguard enable`. Trigger on MGMT1: `ip link set dev br0 type bridge stp_state 1`. Recovery: `ip link set dev br0 type bridge stp_state 0`, then `shutdown` / `no shutdown` on e0/0 (or `errdisable recovery cause bpduguard`).

R5: `no spanning-tree bpduguard enable`, `shutdown`/`no shutdown`, bridge `stp_state 1`; restore with `spanning-tree bpduguard enable` and `stp_state 0`.

## Verification

R2 (captured, fresh import):

```
port              vlan-id
ens2              10
                  20
ens3              10 PVID Egress Untagged
ens4              20 PVID Egress Untagged
br0               1 PVID Egress Untagged
```
PC1 -> 10.90.10.1 and 10.90.10.103: 0% loss; PC2 -> 10.90.20.1: 0% loss; PC3 -> 10.90.20.1: 0% loss. (Before the bridge: PC1/PC2 100% loss, PC3 0%.) `br0`'s own VLAN 1 PVID is harmless.

R3 (captured):

```
MGMT1: bridge fdb show br br0 (dynamic)
52:54:00:46:7e:74 dev ens2 vlan 10      <- PC3 (via ACC1)
52:54:00:11:b6:52 dev ens3 vlan 10      <- PC1
52:54:00:53:38:9e dev ens4 vlan 20      <- PC2
aa:bb:cc:02:7e:00 dev ens2 vlan 10 / 20 <- ACC1 SVIs (also aa:bb:cc:82:7e:00)
ACC1: show mac address-table dynamic
 10  5254.0011.b652 DYNAMIC Et0/0   (PC1)
 10  5254.0046.7e74 DYNAMIC Et0/1   (PC3)
 20  5254.0053.389e DYNAMIC Et0/0   (PC2)
 999 4695.85cb.bac8 DYNAMIC Et0/0   (br0 itself, untagged frames)
```
Et0/0 carries PC1 and PC2: the hypervisor-uplink pattern (many MACs on one port).

R4 (captured; template applied, then `stp_state 1`):

```
Et0/0        MGMT1 ens2   err-disabled bpduguard
%SPANTREE-2-BLOCK_BPDUGUARD: Received BPDU from bridge 4695.85cb.bac8 on port Et0/0 with BPDU Guard enabled. Disabling port.
%PM-4-ERR_DISABLE: bpduguard error detected on Et0/0, putting Et0/0 in err-disable state
```
PC1 -> 10.90.10.1: 100% loss; PC3 -> 10.90.10.1: 0% loss. 4695.85cb.bac8 is br0's MAC.

R5 (captured; guard removed, port bounced, `stp_state 1`):

```
VLAN0001   32768 4695.85cb.bac8  cost 100  Root port Et0/0
VLAN0010   32778 aabb.cc02.7e00  cost 0   (ACC1)
VLAN0020   32788 aabb.cc02.7e00  cost 0   (ACC1)
VLAN0999   33767 aabb.cc02.7e00  cost 0   (ACC1)
vlan 1: Bridge ID 32769 (ACC1)   Et0/0 Root FWD 100 P2p Edge Peer(STP)
vlan 10: Et0/0 Desg FWD 100 P2p Edge
```

R1 values (observed): MGMT1 (Ubuntu 24.04, kernel 6.8.0-59): 1 vCPU, about 2 GB RAM (1968 MB usable), disk /dev/vda1 61 GB, NIC driver virtio_net, `systemd-detect-virt` = kvm, `lscpu`: Hypervisor vendor KVM, full virtualization. PC1 (Alpine): 1 vCPU (/proc/cpuinfo), 469 MB, /dev/vda3 14.5 GB, `readlink /sys/class/net/eth0/device/driver` = virtio_net (`ethtool -i eth0` also works). ACC1 (IOL-L2): a process on the controller, no guest-visible hardware. Ubuntu, Alpine: KVM VMs. No container nodes here (CML service nodes such as syslog/radius are containers).

## Failure / Recovery Behaviour

Clock: a scripted CLI poll, so each value includes 1-2 s of session and poll overhead. CML 2.10.0.

| Scenario (trigger -> end condition) | Runs (s) | Documented range | Basis |
|---|---|---|---|
| Bridge `stp_state 1` -> ACC1 e0/0 err-disabled (template on) | 3, 3, 3 | 1-5 | Bridge hello 2 s; first BPDU triggers the guard |
| Cable pull then restore (ACC1 `shutdown`+`no shutdown`, MGMT1 ens2 down/up) -> first PC1 reply, with `portfast trunk` | 2, 2, 2 | 1-5 | Port forwards at once; restore plus poll |
| Same, without `portfast trunk` (guard on, bridge STP off) | 34, 34, 34 | 28-38 | 2 x 15 s forward delay (derived; the bridge sends no BPDUs to agree with) plus link and poll overhead |

Pull side: PC1 loses connectivity at once (single uplink); PC3 stays up. Failure method named: cable pull = `shutdown` on ACC1 e0/0 plus `ip link set ens2 down`; stopping a CML link does not drop an IOL interface and was not used. Before the template is applied, `show spanning-tree` on e0/0 shows the port as an ordinary trunk port (not edge).

Extra finding: the Linux bridge sends untagged IEEE 802.1D BPDUs (source = ens2's MAC, hello 2 s); ACC1 sends only tagged PVST+ BPDUs, which the bridge cannot use. With the trunk restricted to `allowed vlan 10,20`, ACC1 ignored the untagged BPDUs (received 0): no guard event, no root change, loop risk hidden. With `allowed vlan 10,20,999` the guard fired but roots were unchanged. With VLAN 1 allowed (all VLANs) BPDUs were processed as VLAN 1 (CST).

## Answers to Analysis Questions

1. **Q1** CML on bare metal: the controller is a Linux host running KVM, so the hypervisor is type 1 (KVM sits in the kernel). Run as a VM on a laptop hypervisor, it is a nested guest: a type 2 setup in effect (host OS plus hypervisor), with nested virtualization, lower node density and slower VM nodes (cat8000v, ubuntu); IOL nodes are plain processes and are least affected.
2. **Q2** VM (Ubuntu, Alpine): own kernel and virtual hardware, full isolation, boots in tens of seconds. Container (CML service nodes): shares the host kernel, starts fast, isolated by namespaces. Process (IOL-L2 switch): an IOS binary running directly on the controller's kernel, no guest OS, lightest but not isolated hardware-wise.
3. **Q3** The FDB knows ports of the virtual switch (ens2/3/4 by VLAN) and so the hosts' individual ports, but sees PC3 and the ACC1 SVIs only via the single uplink ens2. ACC1 sees PC1 and PC2 only on Et0/0 (it cannot know there is a bridge behind it) and PC3 on Et0/1. Several MACs on one port is what a hypervisor uplink looks like.
4. **Q4** vSwitches assume a loop-free topology by construction: a frame arriving from an uplink is never forwarded out another uplink, and VM-to-VM traffic stays inside the switch; the physical network handles uplink redundancy (NIC teaming, LACP, load-based or failover policy). They neither run STP nor need it; by default they pass a VM's BPDUs to the uplink (a Linux bridge with STP off forwards them; vSphere drops them only with its guest BPDU filter enabled), so a VM that sends BPDUs reaches the campus switch, which is why the hypervisor port has BPDU guard.
5. **Q5** A hypervisor port should never receive BPDUs from a downstream switch; BPDU guard err-disables the port on the first one, so a mis-tuned or malicious vSwitch cannot join the STP domain. Without the guard, bridge priority 32768 would beat ACC1's 32768 + VLAN ID in VLAN 1 (as seen), so on an unengineered campus the server host could become the root of that VLAN and pull the topology toward itself.
6. **Q6** VLAN 1 changed (root 4695.85cb.bac8, port Et0/0 root port); VLAN 10, 20 and 999 did not. The Linux bridge sends untagged 802.1D BPDUs. In PVST+ a switch maps an untagged IEEE BPDU to the common spanning tree, which is VLAN 1's tree, not the native VLAN's (999). The bridge priority 32768 beats ACC1's VLAN 1 priority 32769 (32768 + 1).
7. **Q7** A trunk limited to 10,20 does not carry VLAN 1, so the untagged BPDUs are ignored (BPDU received 0): no guard event, no err-disable, no root change. It is not safe: nothing is protected, the bridge's STP does not reach ACC1, and a loop through two uplinks would not be blocked. BPDU guard and an allowed list are different controls; the guard needs BPDUs to arrive.
8. **Q8** With `portfast trunk` the port skips listening and learning and forwards at once (2 s); without it the port runs 15 s listening plus 15 s learning (measured 34 s with overhead), because the host bridge sends no BPDUs to agree with (rapid-pvst falls back to timers). One uplink fails all VMs at once: add a second uplink (NIC teaming, ideally to a second switch with LACP or an active/standby policy).
9. **Q9** An `unmanaged_switch` node is a Linux bridge on the controller, so it is a real node that consumes licence and resources even though it has no OS; this lab's bridge is inside the AUTO-MGMT1 guest, invisible to the controller, so it costs no extra node.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), ioll2-xe (IOS XE 17.16.1a), ubuntu (Ubuntu 24.04) |
