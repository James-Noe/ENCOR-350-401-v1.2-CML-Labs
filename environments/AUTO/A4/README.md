# AUTO A4 stage (remote capture: the two-router pod)

Proven by LAB-066.

Built by LAB-066 from A3. MGMT1 files are A3's, unchanged. Credentials, OSPF and the RTR3 behaviour as in `../A0/README.md` and `../A1/README.md`.

**A4 = A3 +** (8 lab nodes plus AUTO-SW and NAT; 9 running nodes)

| Link | A | B | Addressing |
|---|---|---|---|
| RTR1-RTR2 | RTR1 e0/1 | RTR2 e0/0 | 10.90.255.0/31 (RTR1 .0) |
| RTR2-RTR3 | RTR2 e0/1 | RTR3 Gi3 | 10.90.255.4/31 (RTR2 .4) |
| RTR3-RTR4 | RTR3 Gi4 | RTR4 Gi1 | 10.90.255.6/31 (RTR3 .6) |
| PC1 LAN | RTR2 e0/2 | AUTO-PC1 | 10.90.10.0/24 (.1 / .101) |
| PC2 LAN | RTR4 Gi2 | AUTO-PC2 | 10.90.40.0/24 (.1 / .102) |

- **AUTO-RTR2** (iol-xe, Lo0 10.255.90.2) and **AUTO-RTR4** (cat8000v 17.16.1a, `cpus: 2`, Lo0 10.255.90.12): OSPF 1 area 0, point-to-point, cost 10, LAN interfaces passive. RTR4 is not on the API segment (managed in-band through RTR3): local AAA with `CON none` on the console, no HTTP/NETCONF/RESTCONF, `ntp server 10.255.90.1`. No licence line (LAB-068 adds its own).
- **AUTO-RTR1 / AUTO-RTR3**: A3 plus the new links (RTR1 e0/1; RTR3 Gi3 .5, Gi4 .6).
- **Hosts** alpine: PC1 10.90.10.101, PC2 10.90.40.102 (gateway .1). PC2 listens on TCP 22 (sshd) and sends DHCP discovers now and then (seen in ERSPAN captures).
- No monitor session (the student's work). PC1 to PC2 follows PC1-RTR2-RTR3-RTR4-PC2 (traceroute: 10.90.10.1, 10.90.255.5, 10.90.255.7, 10.90.40.102).

**Boot (measured, server shared with LAB-065):** CML says RTR3/RTR4 BOOTED after about 6 min but the day-0 is applied only about 33 min after start (`%CVAC-4-CONFIG_DONE`; `tools/cml-rest.sh log <lab> AUTO-RTR4 5 CVAC`). Do not open the RTR3/RTR4 consoles before that: a connection while CVAC applies leaves a stale priv-1 session (`Bad Password` afterwards; fix: `clear line 0` from an SSH session). On the validation import the first boot of both cat8000v did not apply the day-0 within 67 min; `node stop`, `node wipe`, `node start` on RTR3 and RTR4 (the stored day-0 is kept) gave a working pod in about 4 min. `line vty 0 4 / login local` is rejected under `aaa new-model` (CVAC error, harmless; SSH as admin works).

**Measured on this stage (cat8000v RTR4, 17.16.1a):**
- (a) PASS: `monitor session 66 type erspan-source`, `source interface Gi2 both`, `destination / erspan-id 66 / ip address 10.90.50.31 / origin ip address 10.255.90.12` delivers GRE (protocol 47, 0x88BE, ERSPAN type II) to MGMT1 across RTR4-RTR3 (one routed hop, then L2).
- (b) Copies of frames above the session MTU (default 1464 on the inner frame) are truncated (T bit set), not fragmented or dropped; raising `mtu` to 1500 makes the large copies vanish (DF set, 1536 > 1500).
- (c) PASS: `filter access-group <ACL>` works; removing it needs the session shut/rebuilt (`no monitor session 66`). Re-entering `source interface Gi2 rx` does not replace `both`: `no source interface` first.
- (d) PASS: `apt-get install -y tshark` (4.2.2) via NAT about 1 min; dissects ERSPAN II (Version, Vlan, SpanID, Truncated).
