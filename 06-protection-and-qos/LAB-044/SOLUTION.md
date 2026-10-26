# LAB-044 — Solution

## Summary

Analysis lab (type A, G2) on the live E3 stage (protected Internet edge) with no faults. The student runs a red-team script and watches a beacon (a stand-in for a compromised endpoint) and builds a defence-in-depth argument from Veridian's own counters, logs and flow data. Blueprint: 5.4.a threat defence (Talos, DNS-layer security, network analytics on NetFlow/Stealthwatch, XDR), 5.4.b endpoint security (posture, 802.1X/ISE, EDR/AMP), 5.4.c NGFW (stateful inspection, AVC, IPS, URL filtering, identity) against stateless ACLs and CoPP; 4.2 flows as security telemetry.

Key teaching result: each hostile action is stopped by the ACL, the CoPP or both, and is seen by at least one of ACL log, FNF and CoPP counters. The beacon is permitted (outbound TCP, return traffic matches `established`) and is visible **only** in flow data. Deviation found in build (see Q1): ACL-denied SYNs to tcp 22, 23, 80 and 443 aimed at the edge's own address are mostly counted and dropped by CM-UNDESIRABLE: the ACL denies first, but the `log` keyword and the ICMP unreachable that a denied packet triggers by default each punt a copy to the CPU, where CM-UNDESIRABLE drops it before the log entry (and the ACE counter) is written. Removing `log` alone changes nothing (ACE 0, CoPP 15 in the R2 re-check); only with `no ip unreachables` and no `log` does the ACE count, so only tcp/179 reliably reaches the ACL log; those ports leave a CoPP counter and an FNF record but no `%SEC-6-IPACCESSLOGP` line.

## Intentional Faults

None (analysis lab).

## Diagnosis / Methodology

1. Wait 3 minutes after boot. Baseline: `show ip access-lists EDGE-IN-V4`, `show policy-map control-plane`, `show flow monitor FM-EDGE cache`, BGP/OSPF/HSRP state on HQ-EDGE1.
2. On PROV-SRV1 run `redteam.sh` (about 100 s). Watch HQ-EDGE1 deny counters, DC-SYSLOG1 (`tools/cml-rest.sh log <lab> DC-SYSLOG1 200 IPACCESSLOGP`), CoPP class counters, the FNF cache on e0/0 (provider side) and e0/1 (inside) and the export on DC-NMS1.
3. Beacon discovery: capture the export on DC-NMS1 for 120 s (`tshark -i eth0 -a duration:120 -d udp.port==2055,cflow`), or sample the FNF cache on e0/1 four times 30 s apart (`show flow monitor FM-EDGE cache format table`), and group the records by source, destination and destination port. Look for one inside host (10.10.10.101) with identical small sessions (5 pkts / 274 B) to one outside host (192.0.2.200) on one fixed port (4443) at a fixed period of 30 s, with a new source port each time; ordinary user traffic has no such regularity. Once found, confirm with `-Y 'cflow.dstport==4443 || cflow.srcport==4443'` or `include 4443`. Grade R3 on the student naming host, destination, port, size and rhythm from the data, not on the method. Entries live only 15 s, so a single look can miss it. Compare with the deny counters (unchanged).

## Solution Configuration

No configuration changes. Scripts (day-0, already on the nodes): PROV-SRV1 `redteam.sh` (`hostile.sh all` + `sweep.sh`), `sweep.sh`, `listener.sh` (nc listener tcp/4443, restart loop, started at boot); HQ-PC1 `beacon.sh` (started 45 s after boot: every 30 s `echo hello | nc -w 2 192.0.2.200 4443`, so the period is about 31 s including the session).

## Verification

Start state (fresh import, 3 min after boot):
```
HQ-EDGE1  BGP 10.255.10.32 Up 00:03:58 (5 prefixes), 198.51.100.64 Up 00:03:53 (2); OSPF 3 FULL
          Et0/2 60 110 P Active ... 10.10.60.1 ; Reachability is Up
          show policy-map control-plane | include exceeded [1-9]  -> (nothing)
          260 deny ip any any log   (no matches)
HQ-EDGE2  BGP 10.255.10.31 Up, 203.0.113.64 Up; Et0/2 60 100 P Standby
HQ-PC1    ping 192.0.2.200: 3/3 received ; beacon.sh running
PROV-SRV1 listener.sh running
```
Beacon in the inside monitor (HQ-EDGE1 e0/1, captured):
```
10.10.10.101 -> 192.0.2.200  sport 41817 dport 4443  bytes 274 pkts 5   (e0/1 input, inside address)
192.0.2.200:4443 -> 192.0.2.1:1025  bytes 164 pkts 3                    (e0/0 input, post-NAT view)
```
Export on DC-NMS1 (75 s): 2-4 sessions depending on the export timing (one run captured 2, each record exported twice; capture 120 s to be sure of 4), e.g. sources 35729, 42069, 36629, 35553, destination 4443 every time, each 5 pkts / 274 B out and 3 pkts / 164 B back; the NAT pool translates the source port into 1024-1028.

Beacon versus deny counters (75 s window): `deny ip any any log` 26 -> 26; line 170 (`permit tcp any 192.0.2.0 0.0.0.63 established`) 85 -> 106; EDGE2 all zero; no CoPP class exceeded.

`redteam.sh` run (about 100 s): probe tcp/22, 23, 80, 179, 443 to 198.51.100.65: rc=1 each. Spoof (source 192.0.2.10): 5/5 lost, line 90 (`deny ip 192.0.2.0 0.0.0.127 any log`) +5 matches, logged on DC-SYSLOG1. Web to 192.0.2.130: "web-ok" (line 250). Flood: 3812 sent, 39 answered (98% lost), CM-ICMP `exceeded 3773 packets, 3931466 bytes`; BGP, OSPF, HSRP uptime unchanged, track up.

Sweep of 192.0.2.130 (13 ports, 3 s apart): tcp/80 rc=0, the other 12 rc=1. `deny ip any any log` +9 per sweep; one `%SEC-6-IPACCESSLOGP ... denied tcp 192.0.2.200(sport) -> 192.0.2.130(port)` on DC-SYSLOG1 for each of 21, 25, 53, 110, 143, 445, 3389, 8080, 8443. Ports 22, 23, 443 are absent from the ACL log: CP-UNDESIRABLE matches `tcp any any` 22/23/443 and the denied SYN (logged, and answering with an unreachable) is punted to the control plane, where CM-UNDESIRABLE (police 8000, conform drop) counts it: `conformed 15 -> 18 -> 21 packets` after one nc to tcp/22 (3 SYN retransmits) and one to tcp/23. The client sees an immediate refusal (ICMP admin-prohibited) for logged ports, and a 1 s/3 s timeout (silent) for 22/23/443. FNF cache on e0/0 shows sweep entries (60 B, 1 pkt each, ACL-dropped packets are recorded because the monitor runs before the ACL) for only ~15 s.

After the scripts stop, a fresh re-import plus the start checks equals the first run (no state left behind).

## Failure / Recovery Behaviour

No failure scenarios (analysis lab). Recovery test: scripts end by themselves (redteam about 100 s, flood 40 s, sweep 39 s); the beacon and listener run on. After the scripts stop BGP, OSPF, HSRP and track 10 are in the start state; counters keep their values until the node is wiped. To reset: wipe and restart the nodes, or delete and re-import. Timings (informational, not a convergence claim):

| Scenario (trigger, end condition) | Runs | Documented range | Basis |
|---|---|---|---|
| `redteam.sh` start, script prompt returns | about 100 s (2 runs) | 90-120 s | probe/spoof/web/flood (40 s) + 13 ports x 3 s |
| Beacon, one new FNF cache entry (new source port) | about 30 s apart in 4 of 4 export sessions | 30-35 s | 30 s sleep + about 1 s session + 15 s cache inactive timeout |

## Answers to Analysis Questions

**Q1.** Required answer (observed on the bench):

| Traffic | Saw it | Stopped it | Saw nothing |
|---|---|---|---|
| Probe (tcp 22/23/80/179/443 to 198.51.100.65) | FNF on e0/0 (the monitor runs before the ACL); ACL log and counters for some ports (tcp/179 reliably); CoPP CM-UNDESIRABLE counters for tcp 22/23/80/443 | `deny ip any host 198.51.100.65 log` (only BGP from the peer is permitted) | none |
| Spoof (source 192.0.2.10, Veridian's own space) | DC-SYSLOG1 log, ACL line 90 counter, FNF | line 90, 5 of 5 lost | none |
| Web request to 192.0.2.130 | FNF and the permit counter | nothing: permitted by design | the ACL log (no `log` on a permit) |
| Flood (40 s, large packets) | CoPP counters (CM-ICMP: 3773 packets exceeded, 98 % lost) and FNF | CM-ICMP, not the ACL (echo to the provider-facing address is allowed); BGP/OSPF/HSRP unaffected because they are in CM-ROUTING | none |
| Sweep (13 ports) | nine ports in the ACL log on DC-SYSLOG1; 22, 23 and 443 only as a CM-UNDESIRABLE counter increase; FNF | the final deny | the ACL log for tcp 22, 23, 443 |
| Beacon | FNF only (Q2) | nothing | ACL, syslog, CoPP |

The graded point is the logging gap: a log-based detector undercounts the sweep for tcp 22/23/443, and the CoPP CM-UNDESIRABLE counter rises instead. Platform note for the instructor (not required of the student): the `log` keyword and the ICMP unreachable that a denied packet triggers by default each punt a copy to the CPU, where CM-UNDESIRABLE (`conform-action drop`) drops it before the log entry and the ACE count are written (removing `log` alone does not restore the count; `no ip unreachables` without `log` does). Probes to the edge's own address on tcp 22/23/80/443 therefore mostly count in CM-UNDESIRABLE rather than ACL line 160 (5 probes gave only 1-2 line-160 matches).

**Q2.** Flow data shows a host in the user subnet (10.10.10.101) opening a new, tiny, identical TCP session (5 packets out, 274 B; 3 back, 164 B) to the same outside server on an unusual port (4443) with a new source port every 30 s, around the clock. Fixed size and fixed period (low variance) with no matching inbound request is machine behaviour. A network-analytics product (Cisco Secure Network Analytics, ex-Stealthwatch) baselining NetFlow would raise it as a beaconing/C2 anomaly; Talos reputation on 192.0.2.200 and DNS-layer security (Umbrella) would add intelligence if the server had a name; XDR correlates it with endpoint telemetry (5.4.a).

**Q3.** The beacon: the ACL permits the return traffic with `established` on any outside source and never sees the application; an NGFW with stateful inspection tracks the session in its own table, applies identity (which user/host), application identification (non-standard port, unknown application, not HTTP), IPS signatures and URL/reputation filtering (Talos) and can block or alert on 4443 outbound as a policy decision (outbound is otherwise unrestricted). The sweep: the ACL drops each SYN individually; an NGFW/IPS correlates 13 ports in 40 s from one source as a scan and shuns the source. The web service: the ACL permits tcp 80 to one host and cannot look inside; an NGFW does application visibility and control, IPS, URL filtering and TLS inspection on the permitted traffic (5.4.c).

**Q4.** The beacon starts on a user endpoint. At HQ access, 802.1X/ISE would authenticate the device and user, give the PC only the VLAN/SGT it deserves, and attribute the flow to an identity; posture would quarantine a PC without agent or patches before it starts beaconing; EDR/AMP on HQ-PC1 sees the process that opens the connection and blocks it, which the network cannot. The guest VLAN needs no posture but 802.1X/MAB assigns it, which keeps a guest from reaching the beacon path at all; the DMZ server needs EDR but not 802.1X. 802.1X needs a supplicant on the endpoint, an authenticator that really enforces (the lab's switch image accepts the configuration but authenticates nothing: config-only on ioll2-xe), and an AAA/ISE server with a policy (DC-AAA1 serves RADIUS to router logins only, not EAP).

**Q5.** Suggested ranking (any ranking is acceptable if it is evidence-based). (1) Network analytics on the existing flow export: the only control that saw the beacon is FNF, already exported to DC-NMS1, so the cheapest step turns existing data into alerts. (2) Endpoint security (EDR plus 802.1X/posture) on HQ access: the compromised host is inside and the edge controls are blind to it; EDR names the process. (3) NGFW at the edge: the stateless ACL cannot inspect permitted traffic (web request, beacon) and logs the sweep unevenly; an NGFW closes that. DNS-layer security is a low-cost alternative for (3). Evidence for each: the beacon rows, the permitted web service and the 22/23/443 logging gap.

**Q6.** CoPP protects the router's own control plane (BGP, OSPF, HSRP, management) from being starved by traffic addressed to the router: the flood was throttled at CM-ICMP at 3.9 MB while routing protocols stayed up. Production lesson from Q1: `log` on a high-rate deny ACE and the default ICMP unreachables both punt to the CPU and are themselves subject to CoPP, so configure `no ip unreachables` on Internet-facing interfaces, rate-limit ACL logging, and design the CoPP classes (e.g. CM-UNDESIRABLE) knowing that ACL-log and unreachable punts land in them. An NGFW, EDR and analytics protect hosts and data in transit, not the router's CPU; an NGFW in the path does not police packets sent to the edge's own addresses, and endpoint products do not run there at all.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-25 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), net-tools, radius, syslog, unmanaged_switch |
