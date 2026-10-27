# ENCOR study pack

Hands-on labs for CCNP ENCOR 350-401 v1.2: 78 labs and 5 milestones on Cisco
Modeling Labs.

## How to work a lab
Read [LAB-GUIDE.md](LAB-GUIDE.md) before your first lab. In short:
1. Read `LAB.md` (the brief: scenario, start state, tasks, success criteria). Don't open `SOLUTION.md` yet.
2. Import `LAB-NNN.yaml` into CML (UI: Import Lab, or `tools/cml-rest.sh import LAB-NNN.yaml`) and start it.
3. Do the tasks, and write evidence (command output, measurements) for every Requirement and
   Verification Criterion (V1, V2, …) and an answer to every Analysis Question into the lab's
   `ANSWERS.md`. That evidence is part of the lab.
4. Then compare your evidence and answers with `SOLUTION.md`. To have them graded, open Claude Code in
   this folder and ask it to grade the lab (`CLAUDE.md` holds the instructions; reviews go to the lab's `GRADING.md`).
5. A few labs have no YAML: LAB-073 is deployed with the `csdwan` tool from `BUILD.md`, and LAB-077 is paper analysis.

Modules build on each other, so go in order 01 → 11. A milestone (MS-N) closes modules 03, 05, 07, 09 and 11
and mixes everything up to that point. Labs that say "stage H0", "A2" and so on describe
that start state in `environments/<ENV>/<STAGE>/README.md`; the lab's YAML already contains it.
Where a stage README names node config files (`HQ-CORE1.cfg` and so on), those configs ship
inside the YAMLs of the labs that use the stage, not as separate files.

`tools/cml-rest.sh` (needs `CML_URL`, `CML_USERNAME`, `CML_PASSWORD`) imports labs, reads
service-node logs (`log`) and stops or starts links (`link`), which some labs ask for.

## Labs

### Module 01: toolkit and campus switching

| Lab | Type | Time |
|---|---|---|
| [LAB-001 — Evidence first](01-toolkit-and-campus-switching/LAB-001/LAB.md) | F/A | 75 min |
| [LAB-002 — Trunk Negotiation](01-toolkit-and-campus-switching/LAB-002/LAB.md) | F | 75 min |
| [LAB-003 — Where Did VLAN 20 Go?](01-toolkit-and-campus-switching/LAB-003/LAB.md) | T | 45 min |
| [LAB-004 — EtherChannel bundles](01-toolkit-and-campus-switching/LAB-004/LAB.md) | F | 60 min |
| [LAB-005 — Half the uplink is missing](01-toolkit-and-campus-switching/LAB-005/LAB.md) | T | 45 min |
| [LAB-006 — Spanning tree by design](01-toolkit-and-campus-switching/LAB-006/LAB.md) | I | 90 min |
| [LAB-007 — Loop protection](01-toolkit-and-campus-switching/LAB-007/LAB.md) | F | 60 min |
| [LAB-008 — Seeing the wire](01-toolkit-and-campus-switching/LAB-008/LAB.md) | F | 45 min |
| [LAB-009 — HQ two-tier build-out](01-toolkit-and-campus-switching/LAB-009/LAB.md) | X | 90 min |
| [LAB-010 — Monday Morning at HQ](01-toolkit-and-campus-switching/LAB-010/LAB.md) | T | 75 min |

### Module 02: gateway redundancy

| Lab | Type | Time |
|---|---|---|
| [LAB-011 — First-hop redundancy on routers](02-gateway-redundancy/LAB-011/LAB.md) | F | 90 min |
| [LAB-012 — The redundant distribution block](02-gateway-redundancy/LAB-012/LAB.md) | I | 105 min |
| [LAB-013 — Redundancy by design](02-gateway-redundancy/LAB-013/LAB.md) | A | 90 min |
| [LAB-014 — The OPS floor is cut off](02-gateway-redundancy/LAB-014/LAB.md) | T | 75 min |

### Module 03: ospf and routing design

| Lab | Type | Time |
|---|---|---|
| [LAB-015 — OSPF adjacencies and network types](03-ospf-and-routing-design/LAB-015/LAB.md) | F | 90 min |
| [LAB-016 — Multi-area OSPF](03-ospf-and-routing-design/LAB-016/LAB.md) | I | 90 min |
| [LAB-017 — Two protocols, one topology](03-ospf-and-routing-design/LAB-017/LAB.md) | A/F | 90 min |
| [LAB-018 — Area types](03-ospf-and-routing-design/LAB-018/LAB.md) | F | 75 min |
| [LAB-019 — OSPFv3 and dual-stack routing](03-ospf-and-routing-design/LAB-019/LAB.md) | F/I | 90 min |
| [LAB-020 — Routes That Never Arrive](03-ospf-and-routing-design/LAB-020/LAB.md) | T | 75 min |
| [LAB-021 — HQ goes three-tier](03-ospf-and-routing-design/LAB-021/LAB.md) | X | 150 min |
| [MS-1 — Campus Checkpoint](03-ospf-and-routing-design/MS-1/LAB.md) | M | 180 min |

### Module 04: internet edge and tracking

| Lab | Type | Time |
|---|---|---|
| [LAB-022 — eBGP Neighbours and Best Path](04-internet-edge-and-tracking/LAB-022/LAB.md) |  |  |
| [LAB-023 — Translating Addresses](04-internet-edge-and-tracking/LAB-023/LAB.md) |  |  |
| [LAB-024 — Veridian Goes Online](04-internet-edge-and-tracking/LAB-024/LAB.md) |  |  |
| [LAB-025 — Two Providers, One Policy](04-internet-edge-and-tracking/LAB-025/LAB.md) |  |  |
| [LAB-026 — Measure, Track, React](04-internet-edge-and-tracking/LAB-026/LAB.md) |  |  |
| [LAB-027 — Policy-Based Routing](04-internet-edge-and-tracking/LAB-027/LAB.md) |  |  |
| [LAB-028 — EEM: Automating Evidence](04-internet-edge-and-tracking/LAB-028/LAB.md) |  |  |
| [LAB-029 — Edge Failover](04-internet-edge-and-tracking/LAB-029/LAB.md) |  |  |
| [LAB-030 — The Internet Is Half Down](04-internet-edge-and-tracking/LAB-030/LAB.md) |  |  |

### Module 05: management and segmentation

| Lab | Type | Time |
|---|---|---|
| [LAB-031 — VRF-lite fundamentals](05-management-and-segmentation/LAB-031/LAB.md) | F | 90 min |
| [LAB-032 — An audit finding: device access](05-management-and-segmentation/LAB-032/LAB.md) | I | 75 min |
| [LAB-033 — Central AAA with a safe fallback](05-management-and-segmentation/LAB-033/LAB.md) | F | 90 min |
| [LAB-034 — ACL design for the Veridian site](05-management-and-segmentation/LAB-034/LAB.md) | I | 90 min |
| [LAB-035 — Telemetry and time](05-management-and-segmentation/LAB-035/LAB.md) | I | 120 min |
| [LAB-036 — Flexible NetFlow for the branch server link](05-management-and-segmentation/LAB-036/LAB.md) | F | 60 min |
| [LAB-037 — Hardening HQ](05-management-and-segmentation/LAB-037/LAB.md) | X/N | 180 min |
| [LAB-038 — The Auditors Can't Log In](05-management-and-segmentation/LAB-038/LAB.md) | T | 120 min |
| [MS-2 — Campus, Edge and Services](05-management-and-segmentation/MS-2/LAB.md) | M | 210 min |

### Module 06: protection and qos

| Lab | Type | Time |
|---|---|---|
| [LAB-039 — Reading QoS on a congested link](06-protection-and-qos/LAB-039/LAB.md) | F/A | 120 min |
| [LAB-040 — Control-plane policing](06-protection-and-qos/LAB-040/LAB.md) | F | 90 min |
| [LAB-041 — Filtering inside the VLAN](06-protection-and-qos/LAB-041/LAB.md) | F | 90 min |
| [LAB-042 — Protecting the Edge](06-protection-and-qos/LAB-042/LAB.md) | X/N | 185 min |
| [LAB-043 — Flapping at the Edge](06-protection-and-qos/LAB-043/LAB.md) | T | 150 min |
| [LAB-044 — Security Architecture Review](06-protection-and-qos/LAB-044/LAB.md) | A | 90 min |
| [LAB-045 — Operations Shift 1](06-protection-and-qos/LAB-045/LAB.md) | T/N | 165 min |

### Module 07: wan and tunnels

| Lab | Type | Time |
|---|---|---|
| [LAB-046 — GRE Tunnels](07-wan-and-tunnels/LAB-046/LAB.md) | F | 120 min |
| [LAB-047 — IPsec: Crypto Map and Tunnel Protection](07-wan-and-tunnels/LAB-047/LAB.md) | F | 120 min |
| [LAB-048 — Branch VPNs](07-wan-and-tunnels/LAB-048/LAB.md) | X | 180 min |
| [LAB-049 — BR2 can't reach HQ](07-wan-and-tunnels/LAB-049/LAB.md) | T | 120 min |
| [LAB-050 — Multi-tenant WAN](07-wan-and-tunnels/LAB-050/LAB.md) | X/N | 150 min |
| [LAB-051 — The Fusion Handoff](07-wan-and-tunnels/LAB-051/LAB.md) | I | 120 min |
| [LAB-052 — WAN Operations](07-wan-and-tunnels/LAB-052/LAB.md) | N | 150 min |
| [LAB-053 — A Backup Path Through the Edge](07-wan-and-tunnels/LAB-053/LAB.md) | X | 150 min |
| [MS-3 — Campus and Branches](07-wan-and-tunnels/MS-3/LAB.md) | M | 300 min |

### Module 08: multicast

| Lab | Type | Time |
|---|---|---|
| [LAB-054 — Multicast Fundamentals](08-multicast/LAB-054/LAB.md) | F | 120 min |
| [LAB-055 — Finding the RP](08-multicast/LAB-055/LAB.md) | F | 150 min |
| [LAB-056 — Video for HQ and BR1](08-multicast/LAB-056/LAB.md) | X | 180 min |
| [LAB-057 — No video in the OPS room](08-multicast/LAB-057/LAB.md) | T | 120 min |
| [LAB-058 — Operations shift 2](08-multicast/LAB-058/LAB.md) | T/N | 190 min |

### Module 09: programmability and automation

| Lab | Type | Time |
|---|---|---|
| [LAB-059 — JSON and YANG](09-programmability-and-automation/LAB-059/LAB.md) | F | 90 min |
| [LAB-060 — RESTCONF and NETCONF](09-programmability-and-automation/LAB-060/LAB.md) | F/I | 150 min |
| [LAB-061 — Model-driven change](09-programmability-and-automation/LAB-061/LAB.md) | I | 150 min |
| [LAB-062 — Python for network engineers](09-programmability-and-automation/LAB-062/LAB.md) | A/I | 150 min |
| [LAB-063 — Agent vs agentless](09-programmability-and-automation/LAB-063/LAB.md) | A/I | 150 min |
| [LAB-064 — Under the Hypervisor](09-programmability-and-automation/LAB-064/LAB.md) | A/F | 90 min |
| [LAB-065 — The automation job fails](09-programmability-and-automation/LAB-065/LAB.md) | T | 150 min |
| [LAB-066 — Remote capture: ERSPAN](09-programmability-and-automation/LAB-066/LAB.md) | F | 120 min |
| [MS-4 — Enterprise Operations](09-programmability-and-automation/MS-4/LAB.md) | M | 300 min |

### Module 10: overlays and fabric

| Lab | Type | Time |
|---|---|---|
| [LAB-067 — LISP: Pull, Not Push](10-overlays-and-fabric/LAB-067/LAB.md) | F | 120 min |
| [LAB-068 — VXLAN Between Two VTEPs](10-overlays-and-fabric/LAB-068/LAB.md) | F | 120 min |
| [LAB-069 — The Aster Fabric](10-overlays-and-fabric/LAB-069/LAB.md) | A/X | 180 min |
| [LAB-070 — Group-based policy](10-overlays-and-fabric/LAB-070/LAB.md) | F | 120 min |
| [LAB-071 — Aster Users Can't Reach Shared Services](10-overlays-and-fabric/LAB-071/LAB.md) | T | 150 min |
| [LAB-072 — Operations Shift 3](10-overlays-and-fabric/LAB-072/LAB.md) | T/N | 165 min |

### Module 11: controllers and architecture

| Lab | Type | Time |
|---|---|---|
| [LAB-073 — The SD-WAN Pilot](11-controllers-and-architecture/LAB-073/LAB.md) | A/F | 150 min |
| [LAB-074 — SD-WAN Design Review](11-controllers-and-architecture/LAB-074/LAB.md) | A | 150 min |
| [LAB-075 — Operations Shift 4](11-controllers-and-architecture/LAB-075/LAB.md) | T/N | 150 min |
| [LAB-076 — Catalyst Center and AI workflows](11-controllers-and-architecture/LAB-076/LAB.md) | A | 120 min |
| [LAB-077 — Architecture Review](11-controllers-and-architecture/LAB-077/LAB.md) | A | 120 min |
| [LAB-078 — Aster's service by API](11-controllers-and-architecture/LAB-078/LAB.md) | X/T | 120 min |
| [MS-5 — Final Challenge](11-controllers-and-architecture/MS-5/LAB.md) | M | 325 min |

## License

© 2026 James N. Licensed under [CC BY-NC-ND 4.0](LICENSE): share it unchanged with credit, no commercial use, no derivatives.
