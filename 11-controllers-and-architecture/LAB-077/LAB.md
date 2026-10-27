# LAB-077 — Architecture Review

**Module:** 11 Controllers and Architecture · **Type:** A (Analysis) · **Guidance tier:** G1 · **Estimated time:** 120 min · **Blueprint objectives:** 1.1.a:R, 1.1.b:R

## Scenario

Veridian has merged with Aster, run an SD-WAN pilot and rebuilt its campus twice during the last ten weeks of tickets. The board now asks the network team for an architecture review before the next budget round:

- Should the HQ keep its three-tier design or collapse it to two tiers as it grows?
- Should Veridian extend the fabric approach that Aster already uses to the Veridian HQ?
- Which data-centre services could move to a cloud provider?
- What availability does each option actually buy, and how do we know?

Business requirement from the board: a gateway or routing failure at the campus must not interrupt user traffic for more than 15 s.

You are the reviewer. No lab is built for this exercise. You work from a review pack of measurements taken in the labs you have already done, and you finish with a one-page recommendation for the board.

## Objectives

- Argue a three-tier versus two-tier HQ decision from failure domains, port counts and measured behaviour.
- Say what a fabric would replace at the HQ and what it would add.
- Say which DC services could move to a cloud and what that changes for availability, latency and the WAN design.
- State, layer by layer, which mechanism covers which failure and how long it takes, separating measured from derived values.
- Write a one-page recommendation with risks and a migration order.

## Available Information

**No CML topology.** This is a paper exercise. Everything you need is in the review pack below. Do not start any lab.

### A. Environments you have worked on

```
HQ   H0 flat access -> H1 collapsed core (2 DIST, Po1 interconnect) -> H2 dual WAN edge
     -> H3 management standard (AAA, syslog, SNMPv3, NTP) -> H4 three-tier (2 CORE, 2 DIST, 3 ACC)
     -> H5 single-core lite for the fabric work
EDGE E: Internet edge (dual ISP, tracking), DC-RTR1 uplink to HQ-CORE1
WAN  : provider line + Internet tunnel (GRE over IPsec) HQ-WAN1 <-> BR1-RTR1
DC   : DC-RTR1, DC-SYSLOG1, DC-AAA1 (RADIUS), DC-DNS1 on the DC switch
FAB  : Aster SD-Access-style LISP/VXLAN fabric: SPINE1, BDR1 (border), XTR1/XTR2 (edges), MSMR1, FUS1
SDWAN: Catalyst SD-WAN pilot, controllers only (Manager01, Validator01, Controller01)
```

HQ today: 3 floors, 3 access switches, 2 distribution switches, 2 core routers. The growth plan adds a second building (about 40 % more ports) and a data hall.

### B. Measured and derived evidence (the evidence table)

Every row is quoted from the record of the lab named in the first column. "Measured" values were captured on the CML bench; the platform is software (IOL / IOL-L2), so hardware would usually be faster. Ranges are the lab's documented ranges.

| ID | Source | Layer | Failure | Method | Result | Status |
|---|---|---|---|---|---|---|
| E1 | LAB-010 | Access / EtherChannel | One Po1 member shut (one end only, on a distribution switch) between the distribution switches | one-ended shutdown | 0 % loss (10/10); member back in the bundle immediately | measured |
| E2 | LAB-013 (a), (a2) | Access uplink / STP | ACC uplink cable pull (shutdown both ends) / silent failure (link stop) | (a) cable pull / (a2) silent link stop | about 1 s (1 of 30 lost) / about 4-6 s | measured |
| E3 | LAB-013 (b), (c) | Distribution / HSRP and GLBP | Loss of one distribution switch | node stop | (b) stopping DIST1: about 5 s each direction; (c) stopping DIST2: about 2 s | measured |
| E4 | LAB-013 (e) | Distribution interconnect | Both Po1 members lost | cable pull (shutdown both ends) | 100 % loss between VLANs; no routed path between the distribution switches | measured |
| E5 | LAB-011 R6 | FHRP / HSRP with tracking | Tracked uplink lost (both ends) | cable pull | 0 % loss; HSRP role change 31 s after the track went Down; Active reclaimed about 31 s after recovery (preempt delay 30 s) | measured |
| E6 | LAB-011 R2 reload | FHRP / VRRPv3 | Loss of the VRRP master node | node stop | 4 of 180 pings lost (2.2 %), inside the first about 35 s; master-down timer about 3.6 s | measured |
| E7 | LAB-015 R7 | Routing / OSPF timers | Link failure: hello 10 / dead 40 versus hello 1 / dead 4 | silent link stop | +31.4 to +35.7 s (3 runs; another run 37 s) versus +3.6 s | measured |
| E8 | LAB-021 R5 (a) | Core / VRRP and OSPF | Loss of CORE2 (VRRP master) | node stop | IPv4 about 3 s; IPv6 9-11 s (bounded by the RA lifetime of 12 s) | measured |
| E9 | LAB-047 | WAN / IPsec DPD | Failure of the tunnel path, DPD 10 2 on-demand, OSPF 5/20 | silent link stop | OSPF neighbour lost at 17.5-17.8 s; Tunnel0 down at 20.1-24.6 s (range 18-30 s); recovery 3.4-13.8 s (range 2-15 s) | measured |
| E10 | LAB-067 | Fabric / LISP registration | Link to the mapping system lost | silent link stop | Established flows unaffected; registrations expire after 186-187 s (range 180-190 s); first reply after recovery 6-54 s (range 5-65 s, 1-min negative entry) | measured |
| E11 | LAB-069 | Fabric / border | Border link `no shutdown` after a pull | cable pull (then restored) | First DNS answer 10 s, 11 s, 13 s (range 8-20 s) | measured |
| E12 | LAB-071 | Fabric / mapping system | Loss of the mapping system node | node stop | With caches: no loss for at least 45 s; after cache clear: flows survive about 1 min, then lose packets until the node returns (107 s in one run); a new flow answered 23 s after node start | measured |
| E13 | LAB-074 | WAN / policy and probes | Provider line degraded by 200 ms: voice moves off the line; line cleaned: voice returns | link conditioning (no failure) | Move 11.6-15.8 s (range 5-16 s); return 31.3-34.0 s (range 30-36 s) | measured |
| E14 | LAB-074 | WAN / probe limits | 5 % random loss on the provider line, 300 s window | link conditioning (no failure) | Voice loss 4.6-5.1 %; the loss-blind probe usually does not move voice, but it did in some test runs (probabilistic, 0 to 1 cycles) | measured |
| E15 | LAB-073 | SD-WAN controllers | Loss of Controller01, 5 runs | node stop | Manager sees the control connection down after 14.4-18.5 s; Validator view drops it after 141-152 s; recovery to up on both 118-277 s after node start (node boot 73-145 s) | measured |
| E16 | LAB-073 | SD-WAN Manager API | Unauthenticated and post-logout requests; POST without the XSRF token; Basic auth | none (API requests) | No session and after logout: HTTP 200 + HTML login page (not 401/403/302); POST with session but no X-XSRF-TOKEN: 403; POST /logout: 302; HTTP Basic accepted on this Manager | measured |
| E17 | LAB-013 reference (`derived`) | Chassis / SSO and NSF | Supervisor switchover on a chassis with dual supervisors | none (derived) | SSO keeps hardware forwarding state; OSPF without graceful restart: the adjacency drops, the dead interval (default 40 s) has to expire before the neighbours withdraw its routes, and the adjacency is rebuilt from scratch; with NSF/graceful restart they keep the routes for the grace period. Values from Cisco's published guides, not measured on CML | derived |
| E18 | LAB-075 | Distribution / GLBP | Total loss of one distribution switch: all four of its links stopped (never a node stop) | silent link stop (all four links) | IPv4: 0-5 s when the failed switch is not the STP root, 14-20 s when it is the STP root (ACC re-converges); IPv6: 8-14 s (non-root) / 14-22 s (STP root), driven by default-router expiry (RA router lifetime 12 s), plus STP re-convergence when the root is lost; GLBP hello 1 s / hold 3 s | measured |

Notes you should use: E15's Manager and Validator views disagree for more than two minutes, so say which view you trust. E10 and E12 depend on the mapping system, a single node in the pack. The Method column uses the four failure methods of R4 (cable pull, silent link stop, one-ended shutdown, node stop); a node stop is a whole-chassis loss, silent for the neighbours. E13 and E14 are link conditioning, not failures; E16 and E17 have no failure method.

### C. Option sheets (fictional figures)

| | Option 1: keep three-tier and add a distribution pair for building 2 | Option 2: collapse to two-tier (collapsed core, Layer 2 access) | Option 3: fabric at HQ (Aster approach) |
|---|---|---|---|
| Capital cost | USD 310 000 | USD 190 000 | USD 520 000 |
| Annual licence and support | USD 38 000 | USD 29 000 | USD 96 000 (controller and DNA-style licensing) |
| Port capacity | 480 access ports, 20 % spare | 336 ports, 5 % spare; a third DIST pair needed for 10 % growth | 600 ports, 25 % spare |
| Staff skills | In place | In place | New: LISP, VXLAN, controller operations (training USD 24 000) |
| Delivery | 14 weeks | 8 weeks | 30 weeks, in two waves |
| Constraint | More devices to patch; two layers of FHRP and routing | VLANs span more switches; larger STP scope; one distribution pair carries all routing | Controller dependency; border and mapping system become single failure points unless doubled (USD 70 000) |

| Cloud option for DC services | Move | Keep | Annual saving | Constraint |
|---|---|---|---|---|
| DNS and DHCP | Yes | local cache at HQ | USD 12 000 | branch DNS must survive a WAN loss |
| AAA (RADIUS) | Maybe | local fallback accounts | USD 9 000 | console AAA exemption; latency over the tunnel |
| Syslog and NMS | Yes | none | USD 15 000 | log volume over the WAN; the lines are 100 Mbit/s |
| WAN | Provider line plus Internet tunnel today; the SD-WAN pilot shows an alternative | | | see E9, E13-E16 |

Credentials: none are needed.

## Starting State

Paper exercise: no devices. You have the review pack above, and your own notes from the labs named in it. The pack is the only source for the figures you quote; do not re-measure.

## Requirements / Change Requests

**R1.** HQ tiers. Argue for keeping three tiers or collapsing to two for Veridian's growth plan. Cover failure domains, STP scope, OSPF area design, port counts and cost, and cite at least three evidence-table rows by ID.

**R2.** Fabric. State what an SD-Access-style fabric would replace at the HQ (VLAN and STP stretch, gateways, segmentation, policy) and what it would add (controller dependency, licensing, skills). Use at least two rows from E10-E12 or your fabric labs.

**R3.** Cloud. Say which DC services could move (DNS and DHCP, AAA, syslog and NMS), and what changes for availability, latency and the WAN design. Use at least one WAN row (E9, E13 or E14).

**R4.** Availability per layer. Produce a table: for each layer (access, distribution/core, FHRP, WAN, controller, chassis), which mechanism covers which failure, the time it takes, and whether the value is measured or derived. Name the failure method behind each value, taking it from the evidence table's Method column (cable pull, silent link stop, one-ended shutdown, node stop).

**R5.** Recommendation. One page: the option you recommend, the risks, a migration order with the reason for the order, and the evidence rows you rely on.


## Verification Criteria

**V1.** Every figure in your memo carries an evidence ID and agrees with the pack; derived values are marked.

**V2.** R1 cites at least three measured rows and states what each measurement does and does not show.

**V3.** R2 lists at least one thing the fabric removes and at least one new dependency it creates.

**V4.** R3 states a failure of the WAN and what each moved service would do during it.

**V5.** R4 covers every layer, uses one failure method per value and shows a time or a stated reason why none exists.

**V6.** R5 fits one page, names a first step that can be reversed, and states two risks with an owner for each.


## Analysis Questions

**Q1.** Where would a two-tier design's failure domain have hurt in a ticket you solved earlier in the course?

**Q2.** What does FHRP not protect against that SSO/NSF does, and the reverse?

**Q3.** Which failure in a fabric is worse than in a traditional campus, and which is better? Use E10-E12.

**Q4.** What does a cloud move do to your troubleshooting toolkit?

**Q5.** Which of your own measurements do you trust least, and why?

