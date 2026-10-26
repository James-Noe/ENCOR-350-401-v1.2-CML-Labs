# EDGE E2 stage baseline (dual ISP with tracked failover)
Built and proven in CML by LAB-029. Start point for LAB-030 (E2 with faults), the E3 protection stage (module 06) and MS-4.

**Configs.** The routers carry their running configuration after LAB-029's solution, cold-boot tested (both BGP sessions per edge, track 10 and 20 Up, tracked static defaults, HSRP 110 Active, the ISPA-EVIDENCE applet and the PC1 traceroutes match the solved lab). HQ-CORE1, PROV-ISP1, PROV-ISP2 and the hosts are identical to E1 (the stage changes only the two edges).

**Profile and topology:** identical to E1 (`environments/EDGE/E1/README.md`): 8 nodes licensed, 10 running by the budget tool (two unmanaged switches count).

## Stage content (E2 on top of E1)
- HQ-EDGE1: static routes `198.51.100.1/32` via Ethernet0/0 198.51.100.64 and via Null0 AD 250 (probe pinning, rule 16); `ip sla 10` icmp-echo 198.51.100.1 source Ethernet0/0, frequency 5 (default timeout 5 s), schedule forever; `track 10 ip sla 10 reachability` with `delay down 5 up 30`; `ip route 0.0.0.0 0.0.0.0 198.51.100.64 track 10`; HSRP 60 on Ethernet0/2 `track 10 decrement 20` (priority 110 -> 90); EEM applet ISPA-EVIDENCE (`event track 10 state down`, `enable` first, appends clock, default route, track, SLA statistics and BGP summary to `unix:ispa-evidence.txt`, then logs "ISP-A evidence captured"). `flash:` does not exist on iol-xe, hence `unix:`.
- HQ-EDGE2: the same for ISP-B (203.0.113.1/32 pinned, `ip sla 20`, `track 20`, tracked default); HSRP 60 stays priority 100 untracked; no applet.
- The OSPF default origination keeps no `always`: the tracked static leaving the table withdraws the OSPF default (EDGE2's metric-30 default then takes over).

## Measured behaviour (LAB-029; UTC log timestamps, hosts ping 1/s)
- **Silent failure EDGE1-ISP1** (`link stop`): track 10 Down 15-17 s later (frequency 5, timeout 5, delay down 5); evidence logged +16 s; HSRP priority 90 (EDGE1 leaves Active 1 s after track Down, Standby 12 s after); CORE1 default via EDGE2 (E2 metric 30) and PC1 -> PROV-SRV1 loses 14-15 pings, then leaves via ISP-B. ISP-A's eBGP session stays Up until the 180 s hold expires (IPv4 about +130-180 s, IPv6 +130-180 s); inbound DMZ traffic and ISP-A's own networks wait for it (HQ-SRV1 -> PROV-SRV1 lost ~130-175 pings).
- **Recovery** (`link start`): IPv4 BGP Up +25 s, track Up +35 s (first probe + delay up 30), default and HSRP back, 0 lost pings.
- **Cable pull ISP-A** (`shutdown` both ends): BGP down and static default withdrawn at once (0 of 120 pings lost), track Down +6 s, probe `show ip route 198.51.100.1` = Null0 AD 250 (no leak), evidence file written.
- **Silent failure EDGE2-ISP2**: track 20 Down +16 s; default-routed traffic unaffected (EDGE1 primary); traffic to ISP-B's networks lost ~147 pings until its BGP hold expired (+148 s), then via ISP-A and the interconnect. Cable pull ISP-B: 0 lost pings.
- **Node stop EDGE1** (saved first): PC1 -> PROV-SRV1 loses 3 pings (OSPF dead 4 s), EDGE2 HSRP Active at once; HQ-SRV1's Internet traffic is lost roughly 100-150 s (replies return via ISP-A, whose session to the dead EDGE1 stays Up until hold expiry +177 s). EDGE1 restart: track Up +30 s after boot, HSRP preempts back.
- IPv6: the default comes from ISP-A's BGP ::/0, so a silent failure recovers only at hold expiry (130-180 s; LAB-030 saw IPv6 recover between +30 s and +180 s); an IPv6 cable pull loses 8-9 pings before OSPFv3 moves the default (LAB-029 SOLUTION Q3). HQ-EDGE1's DMZ interface advertises `ipv6 nd router-preference High`, so HQ-SRV1's IPv6 default prefers EDGE1 and does not follow HSRP 60 or track 10.
- **AI applet:** as proposed (`Up->Down`) it never fires; with the pattern fixed it runs, logs success but writes no file (no `enable`); the corrected applet writes the file on every ISP-A failure, cable pull included.

**The lab YAML of 029 is a pre-staged start state (E1), not the stage.** LAB-030 starts from these configs with faults injected.
