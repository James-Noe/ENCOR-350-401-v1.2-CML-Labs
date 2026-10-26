# HQ lite H-TS: group-based policy (built by LAB-070)
Proven by LAB-070. Cold-boot checked from these files (9 nodes BOOTED in 118 s; every check below passed on the booted stage).

**Profile (9):** HQ-CORE1 (iol-xe), HQ-DIST1, HQ-DIST2, HQ-ACC1 (ioll2-xe), HQ-PC1 (VLAN 10), HQ-PC2 (VLAN 20), HQ-PC3 (VLAN 50, encoder + busybox `httpd -p 80` in its day-0), DC-RTR1, DC-AAA1. Same cabling as HQ lite H4 without HQ-PC5; ACC1 Ethernet1/2 is `shutdown`. Configs are the H4 lite configs plus the CTS lines below.

**CTS configuration (what held on this platform):**
- Groups: 10 EMPLOYEES (PC1), 20 OPERATIONS (PC2), 50 SERVERS (PC3), 2 NETWORK (the trunks). Classification by `cts role-based sgt-map <ip> sgt N` on ACC1 and on HQ-CORE1 (accepted; `sgt-map vlan-list` is accepted but creates no visible binding).
- Propagation: `cts manual` + `policy static sgt 2 trusted` on ACC1 e0/0-e0/1 and DIST1/DIST2 e0/0-e0/2. `cts manual` is rejected on a Port-channel and on a member of a bundle ("first remove from port channel"), so the lines sit on the members before `channel-group` (works from day-0 and when the member is taken out and put back, the bundle stays Po1(SU)).
- SGACLs and matrix: WEB-ONLY (tcp 80), PING-WEB (icmp, tcp 80), DENY-ALL; 10->50 WEB-ONLY, 20->50 PING-WEB, 10<->20 DENY-ALL; every other cell default permit.
- Enforcement: `cts role-based enforcement` on ACC1 (with `vlan-list 10,20,50`) and on HQ-CORE1.

**Measured:**
- (b) No CMD on the wire: a capture without filter on DIST1 e0/2 - ACC1 e0/0 during PC1 -> PC3 traffic holds only dot1q 0x8100 frames (no 0x8909). `show cts interface` shows Peer SGT 2 / Trusted / Propagate Enabled, IFC OPEN. The ioll2-xe CMD is control-plane only here.
- (c) ACC1 (pure L2, `no ip routing`): `cts role-based enforcement vlan-list` is accepted, counters stay 0, nothing is filtered (all PC1/PC2 flows pass, ping and web). Enforcement works only on a routed hop: tested on DIST1 (SVI/interfaces) and on HQ-CORE1 (global command; counters From 10 to 50 etc.). With no binding for the source, the source group is unknown, the cell is not matched and the flow passes with no counter. The source group is not learned from the tag (no CMD), so option (1) (ACC1 bindings) fails; the working mechanism is the IP-to-SGT bindings on the enforcement point, HQ-CORE1, which sees every inter-VLAN flow whichever path (DIST1 or DIST2) the frame took.
- SXP (option 2): `cts sxp` is accepted on ACC1 (speaker) and CORE1 (listener, which listens on tcp 64999 and sees the connection attempt) but the connection stays `Off` (default password and `password none`, 4+ min); static bindings on CORE1 are the stand-in.
- (d) CORE1 (iol-xe): `cts manual` rejected on dot1q subinterfaces; accepted on the physical Ethernet0/1 but IFC stays INIT (peer not OPEN). CORE1 does not carry or keep a tag, so option (3) fails. CORE1 does enforce SGACLs from its static bindings.
- Counters after the policy test (CORE1, from `clear`): 10->50 permitted 5 (web), denied 6 (3 pings from PC1 + the 3 echo replies when PC3 pings PC1); 20->50 permitted 8 (3 pings + web); 10->20 denied 3; 20->10 denied 3. SGACLs are stateless per direction, so PC3 -> PC1 ping fails (the reply is group 10 -> 50 ICMP).
- Failure test: with ACC1 e0/0 and DIST1 e0/2 shut, the same results via DIST2 and Po1.
