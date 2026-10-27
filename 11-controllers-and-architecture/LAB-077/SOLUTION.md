# LAB-077 — Solution

## Summary

Type A, G1, no CML topology. Blueprint: 1.1.a (two-tier, three-tier, fabric and cloud designs: analysed as a design argument) and 1.1.b (redundancy, FHRP, SSO/NSF: analysed with measured and derived timings). The student synthesises evidence from earlier labs into a board memo; nothing is built. The learning point is the discipline of quoting a measurement with its lab, method and status, and of seeing what each mechanism does not cover.

Source rule: every value in LAB.md section B was copied from a SOLUTION record that existed when this lab was built. Rows E1-E14, E17 and E18 come from validated SOLUTION.md files of the named labs (LAB-074 is PASS WITH NOTES; its 5 % loss outcome is probabilistic and says so). Rows E15 and E16 come from `labs/LAB-073/SOLUTION.md` (Failure / Recovery Behaviour for E15; Verification R4 for E16).

Build notes: (1) the GLBP row E18 comes from the validated LAB-075 Failure / Recovery table (silent total loss of a distribution switch), added after LAB-075 was validated; the other GLBP/HSRP times come from LAB-013. (2) The HQ and DC option-sheet figures are fictional. (3) The pack quotes "controller loss in 073" as E15 and adds E16 (Manager API behaviour) because the 073 record has it and Q2/Q4 can use it.

## Intentional Faults

Not applicable (analysis lab).

## Diagnosis / Methodology

Method for the reviewer (and for a marker): (1) fix the decision question, (2) pick the evidence rows that bear on it, (3) state for each row what failure, method and status it describes, (4) say what the row does not show, (5) only then recommend. Marking points for traps in the pack:

- Cable pull versus silent failure: E2 (1 s versus 4-6 s) and E7 (3.6 s versus 31-37 s) show the same link detected at different speeds; an answer that compares E5 (cable pull, 0 % loss) with E9 (silent failure) as if equal is wrong.
- A node stop is a chassis loss, not a supervisor switchover (LAB-013 R4); only E17 (derived) speaks about SSO/NSF.
- E14 is probabilistic (0 transitions in 3 of 3 runs in one series; one run with a Down/Up cycle in another). A memo that says "the probe never reacts to loss" or "always reacts" overstates.
- E15: the Manager's control view drops in 14-19 s, the Validator view in 141-152 s, the device list is unreliable (stale). A memo should say which view was used.
- E16: unauthenticated and post-logout requests give HTTP 200 with an HTML login page, so a script that tests only the status code is wrong; Basic auth is accepted on this Manager (measured).
- E10/E12: fabric traffic with warm caches survives mapping-system loss for a while; the damage begins with new flows and cache expiry. E12 and E10 depend on one MSMR node in the lab.

## Solution Configuration

None (no devices). A reference rubric follows in place of configuration.

### Rubric (R1-R5)

| Req | Full marks need | Common errors |
|---|---|---|
| R1 | A clear choice for Veridian's growth plan with reasons: failure domain (E3, E4, E8 show how a distribution pair or its interconnect bounds the damage), STP scope (E2 a/a2), OSPF area/summary design, port capacity (option sheet: collapsed design leaves 5 % spare, below the plan), cost (USD 310k + 38k/yr versus 190k + 29k/yr). At least 3 IDs. Either choice is accepted if the argument holds; the weak points of two-tier (collapsed core, Layer 2 access, as on the option sheet) are the single distribution pair as the failure domain for all gateways, routing and uplinks (E4), its port capacity (5 % spare) and VLANs and STP spanning more access switches (E2 a/a2, E18); if a student instead assumes routed access, accept it only with its own consequences (no VLAN spans access switches, STP stays local to each switch, but every access switch needs a routed link and its own subnets), and mark down an answer that mixes the two; the weak point of three-tier is more devices and two FHRP/routing layers | Quotes a lab number without the figure; counts E5 (0 % loss) as proof of a fast failover when only the role change took 31 s |
| R2 | Removes: VLAN/STP stretch to the edge, gateway sprawl, manual segmentation; adds: controller and mapping-system dependency (E10-E12), licensing (USD 96k/yr), LISP/VXLAN skills, 30-week delivery; notes the border (E11) and doubled MSMR cost | Treats the fabric as "no STP, no failures"; ignores E12 |
| R3 | DNS/DHCP and syslog/NMS move more easily; AAA needs local fallback (console AAA exemption, tunnel latency); WAN loss makes the cloud services unreachable unless cached; ties to E9 (DPD 18-30 s) and E13/E14 (path move 5-16 s, return 30-36 s, loss not seen by a delay probe) | Moves AAA with no fallback |
| R4 | Table with all six layers: access (E1, E2), FHRP (E3, E5, E6, E18), routing (E7, E8), WAN (E9, E13, E14), controller (E15), chassis (E17 derived). Each value with its method (the evidence table's Method column) and status. A memo that cites only E3/E8 for the 15 s claim and omits E18's STP-root row loses marks (selective evidence) | Mixes failure methods; presents E17 as measured; no value for controller loss data plane (the answer: the data plane continues, E15 says only control connections were observed) |
| R5 | One page, a recommendation, two risks with owners, a reversible first step (for example: pilot the fabric on the new building, or retain three tiers and raise port capacity), a migration order with reasons, evidence IDs | Recommends with no migration order; cites derived values as measured |

A model recommendation (one of several acceptable): keep three-tier for the existing HQ and add the second building as a distribution pair (Option 1). Against the board's 15 s requirement (LAB.md scenario) the evidence is split: E3 and E8 (2-11 s) and E18 for a non-root distribution switch (0-5 s IPv4) meet it, but E18 when the lost switch is the VLAN's STP root shows 14-20 s IPv4 and 14-22 s IPv6, which does not reliably meet 15 s. So the recommendation must carry a mitigation for the root case: place the STP root and the gateway role deliberately (root on the switch whose loss is less costly, or split roots per VLAN), tune RSTP failover toward the root, and re-measure, or accept the risk with a named owner; move syslog/NMS and DNS/DHCP to the cloud first (reversible), AAA last with local fallback; run the fabric as a pilot in the new building only (Option 3 in one wave), because E10-E12 show the mapping system and the border are new single failure points and the team has no LISP operations record. Risks: mapping-system loss with cache expiry (owner: network lead); cloud services unreachable during a WAN failure of 18-30 s (owner: WAN lead).

## Verification

Check of every quoted value against its source (done by reading the source file; no CML used):

| ID | Source file and location | Quote check |
|---|---|---|
| E1 | 01-.../LAB-010 SOLUTION, Failure / Recovery | 10/10, 0 % loss: matches |
| E2, E3, E4 | 02-.../LAB-013 SOLUTION, outage summary table | matches (a) about 1 s, (a2) 4-6 s, (b) about 5 s, (c) about 2 s, (e) 100 % loss |
| E5, E6 | 02-.../LAB-011 SOLUTION, Failure / Recovery | matches (31 s, 4/180) |
| E7 | 03-.../LAB-015 SOLUTION, R7 table | +33.0, +35.7, +31.4 s and +3.6 s (the LAB.md range is 31.4-35.7); another run 37 s |
| E8 | 03-.../LAB-021 SOLUTION, R5 (a) | about 3 s IPv4, 9-11 s IPv6 |
| E9 | 07-.../LAB-047 SOLUTION, timing table | matches |
| E10 | 10-.../LAB-067 SOLUTION, timing table | matches |
| E11 | 10-.../LAB-069 SOLUTION, timing table | matches |
| E12 | 10-.../LAB-071 SOLUTION, Failure / Recovery | matches |
| E13, E14 | 11-.../LAB-074 SOLUTION, timing table | matches, including 4.6-5.1 % and the probabilistic outcome |
| E15, E16 | `labs/LAB-073/SOLUTION.md`, Failure / Recovery Behaviour (E15) and Verification R4 (E16) | values copied from the SOLUTION |
| E17 | 02-.../LAB-013 SOLUTION, R4 and Reference Material Sources | derived, marked |
| E18 | 11-.../LAB-075 SOLUTION, Failure / Recovery table (DIST1 and DIST2 stop rows) | matches 0-5 s / 14-20 s IPv4, 8-14 s / 14-22 s IPv6 |


## Failure / Recovery Behaviour

Not applicable: paper lab. The failures are earlier labs' measured failures, cited in LAB.md section B.

| Scenario (trigger, end condition) | Runs | Documented range | Basis |
|---|---|---|---|
| none measured in this lab | n/a | n/a | the evidence table quotes other labs' records |

## Answers to Analysis Questions

**Q1.** Any ticket where one distribution pair or its interconnect carried several VLANs qualifies. Example: LAB-013 (e): with both Po1 members lost, cross-VLAN traffic stopped completely (E4). In a collapsed two-tier design the same pair is also the routing and WAN attachment point, so one failure takes out gateways, routing and uplinks together. Accept any ticket the student actually solved if the failure domain is named.

**Q2.** FHRP covers loss of a gateway: the virtual address moves (E3 2-5 s, E5 31 s role change, E6 about 3.6 s master-down, E18 GLBP silent total loss 0-5 s IPv4 for a non-root switch and 14-20 s when the lost switch is the STP root; that longer time is ACC1 STP re-convergence plus the 4 s OSPF dead time on the return path, with GLBP's 3 s hold inside it, not a GLBP failover time; IPv6 is 8-14 s / 14-22 s, driven by default-router expiry (RA lifetime 12 s) plus STP when the root is lost; it is a second silent-failure example to contrast with E3's node stop). It does not protect the control plane inside one chassis or the forwarding state during a supervisor failure, and it does nothing for a failure behind the gateway. SSO/NSF (E17, derived) protects against loss of one supervisor in a chassis: forwarding continues and, with graceful restart, neighbours keep routes; it does not help when the whole chassis or its uplinks fail, where FHRP and redundant paths do. Our node stops (E3, E6, E8) are chassis losses, so SSO/NSF would not have shortened them.

**Q3.** Worse: the mapping system, border and controller are shared dependencies; E12 shows new flows failing while the mapping system is down and E10 shows registrations expiring after about 186 s; E11 shows the border adds 8-20 s on recovery. Better: no STP in the overlay, so the STP re-convergence cases (E2 a2, 4-6 s) and L2 loops do not span the fabric; failover of a fabric edge uplink is routing, not STP (derived from the fabric design; not measured in the pack).

**Q4.** Fewer device-level commands: the controller and cloud portals hide state, so packet capture and `show` outputs on the DC services are replaced by API calls and logs. E16 shows the API itself needs care: HTTP 200 with an HTML login page on no session, XSRF token for POST, Basic accepted. Time to detect differs by view (E15: 14-19 s versus 141-152 s). The toolkit must include latency to the cloud and a local fallback.

**Q5.** Open. Good answers name a specific row and a reason: E15 (the Validator and Manager views disagree; mechanism of the 141-152 s not established), E14 (probabilistic outcome), E10 first-reply spread (6-54 s from the 1-min negative entry), or any row measured with a 1-s ping loop. Weakest overall: E15 recovery (118-277 s, runs 2-5; run 1 not measured) and E17 (derived).

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | none (paper analysis) |
