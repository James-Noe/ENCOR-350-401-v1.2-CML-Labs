# LAB-036 — Solution

## Summary
Foundation lab on Flexible NetFlow (blueprint 4.2:I): flow record (match/collect), exporter, monitor, per-interface input attachment, cache reading and sorting, NetFlow v9 export decoded with `tshark`. Reinforces the NMS-and-capture method of LAB-035. No faults.

**Platform note:** the iol-xe `flow monitor` has no `cache timeout`, `cache type` or `cache entries` commands (all `% Invalid input`; `?` offers only collect, description, exporter, record, statistics). The timeouts are fixed at inactive 15 s and active 1800 s (`show flow monitor`). So R2 relies on the 15 s inactive timeout, and Q2 asks you to read the values.

## Intentional Faults
None.

## Diagnosis / Methodology
Not a troubleshooting lab. Suggested method: build record, exporter, monitor, attach the monitor to e0/1 and e0/2 (input), start `tshark` on DC-NMS1 before generating traffic, run `iperf -s -D` on SRV1, then ping, wget and `iperf -c` from PC1, read the cache, then the capture.

## Solution Configuration
R1:
```
flow record REC-BRANCH
 match ipv4 source address
 match ipv4 destination address
 match ipv4 protocol
 match transport source-port
 match transport destination-port
 match interface input
 collect counter bytes
 collect counter packets
 collect timestamp sys-uptime first
 collect timestamp sys-uptime last
flow exporter EXP-NMS
 destination 10.50.50.60
 source Loopback0
 transport udp 2055
 template data timeout 60
flow monitor MON-BRANCH
 record REC-BRANCH
 exporter EXP-NMS
interface Ethernet0/1
 ip flow monitor MON-BRANCH input
interface Ethernet0/2
 ip flow monitor MON-BRANCH input
```
Test traffic and capture:
```
SRV1:    iperf -s -D
DC-NMS1: tshark -l -i eth0 -f "udp port 2055" -d udp.port==2055,cflow -c 40 > /tmp/cf.txt 2>&1 &
PC1:     ping -c 5 10.0.20.20 ; wget -q -O - http://10.0.20.20/ ; iperf -c 10.0.20.20 -t 10
```
Read the result with `cat /tmp/cf.txt` on DC-NMS1. Add `-T fields -e cflow.srcaddr -e cflow.dstaddr -e cflow.protocol -e cflow.srcport -e cflow.dstport -e cflow.octets -e cflow.packets -e cflow.inputint` to a `-r` of a saved capture to see values (several records in one packet print comma-joined).

## Verification
Captured on R1:
- `show flow exporter EXP-NMS`: NetFlow Version 9, source 10.255.0.1 (Loopback0), destination 10.50.50.60, UDP 2055.
- `show flow monitor MON-BRANCH`: Inactive timeout 15 s, Active timeout 1800 s. Reading order matters (Q2): a student who runs ping, HTTP, then a 10 s iperf and reads the cache more than 15 s after the ping and HTTP packets sees only the iperf flows, because the idle flows were aged out and exported. Read the cache within 15 s of the last ping and HTTP packet, or start the iperf stream first.
- `show flow monitor MON-BRANCH cache sort highest counter bytes top 5`: first entry 10.0.10.10 -> 10.0.20.20 TCP dport 5001, Et0/1, 42304780 bytes / 28207 packets; second the reverse direction (input Et0/2, 636856 bytes); then DHCP 68 -> 67 flows from the Alpine hosts (Et0/1 and Et0/2) and the HTTP reply 80 -> client port on Et0/2 (489 bytes). The ICMP flows are also in the cache.
- On DC-NMS1 `tshark` lines like `10.255.0.1 -> 10.50.50.60 CFLOW 147 total: 2 (v9) records ... [Data-Template:257] [Data:257]`. Decoded iperf row: protocol 6, sport 45194, dport 5001, 27703752 octets, 18474 packets, input ifIndex 2 (Et0/1); reverse row 5001 -> 45194, 436264 octets, 8302 packets, ifIndex 3 (Et0/2). (Separate runs from the cache figures above, so the byte counts differ.)
- The template ID changed between runs (256, then 257 after the monitor was re-attached).

## Failure / Recovery Behaviour
Silent failure: `link stop` on R1 e0/0 - DC-RTR1 e0/0 (stop and restart the link with `tools/cml-rest.sh link`), exporter statistics cleared and `tshark` running on DC-NMS1.
- PC1 -> SRV1 traffic is local to R1 and unaffected; the cache keeps counting (Flows added 43 -> 49).
- After about 35 s R1 reported `Successfully sent: 9` while the NMS had captured 2 packets; after restore R1 reported 18 sent against 5 captured. The exporter counts packets as sent even though the link silently drops them: compare with the capture.
- Capture timeline: packets at 0 s and 8 s, gap until 142 s (link restored at about 110 s), data resumed at 142/149 s and a Data-Template packet at 155 s. The template is resent on its 60 s timer, so the collector can decode again without any action.
- Records exported during the outage are lost, not queued.

## Answers to Analysis Questions
**Q1.** A packet is accounted where it enters R1: a flow from PC1 to SRV1 is counted on e0/1 input, and the replies on e0/2 input, so each packet is seen once, with the reverse direction as a separate flow with its own input interface. Adding output on both would count every forwarded packet twice (once at ingress, once at egress), doubling the byte and packet totals, and the record would be matched with an output interface in the other direction.
**Q2.** The router uses fixed values here: inactive 15 s (a flow with no packets for 15 s is aged out and exported) and active 1800 s (a flow that stays busy is exported and refreshed at least every 30 min). For a minutes-long iperf stream the flow stays in the cache and is exported only after it ends (observed) or at the 30 min mark; a shorter active timeout would give the collector periodic partial totals during the stream, at the price of more export traffic. They cannot be changed on iol-xe.
**Q3.** The template (Data-Template, v9 template flowset) describing the fields of each data record goes in the first export packet and again every `template data timeout` (60 s here because the solution sets `template data timeout 60`; the IOS default is 600 s, shown only by `show run all | section flow exporter`). A v9 data record has no field names; without the template the collector cannot decode it, and after an outage or a collector restart it must wait for the next template.
**Q4.** NetFlow gives who talked to whom, how much and when, summarised per flow, at low cost and long retention; it cannot show payload or application content. A flexible record can carry the OR of the TCP flags seen in a flow (`collect transport tcp flags`), but not per-packet sequence, handshake timing or retransmissions. Note that a flow record cannot be edited while a monitor uses it (IOS answers `Object is in use`). The order that worked: remove the monitor from the interfaces (`no ip flow monitor ...`), delete the monitor (`no flow monitor MON-BRANCH`), edit the record, then recreate the monitor and re-attach it. A capture shows every packet and its content, but only where it is taken, for a short time, and with high volume; it cannot give an aggregated view across devices.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), net-tools |
