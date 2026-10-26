# FAB F1 stage (two-VN fabric, border in the underlay, no exit; LAB-069 start state)
Proven by LAB-069.
Built by LAB-069 (its start state). Profile: 10 nodes: FAB-MSMR1, FAB-SPINE1, FAB-XTR1, FAB-XTR2, FAB-BDR1, DC-FUS1, DC-RTR1 (iol-xe), FAB-PC1, FAB-PC2 (alpine), DC-DNS1 (dnsmasq).

## Cabling and addressing
F0 underlay + SPINE1 e0/3 - BDR1 e0/3 10.60.255.6/31 (SPINE1 .6, BDR1 .7); BDR1 e0/0 - DC-FUS1 e0/1 (dot1q 3001/3002, F-H); FUS1 e0/0 - RTR1 e0/2; RTR1 e0/3 - DNS1 eth0. PC1 10.60.10.101 (CORP, XTR1 e0/1), PC2 10.60.21.102 (IOT, XTR2 e0/1), gateways .1; EID loopbacks XTR2 Lo11 (CORP 10.60.11.1/24), XTR1 Lo20 (IOT 10.60.20.1/24). Both PCs resolve through 10.50.51.53.

## Content
F0 plus: VRF IOT (rd 65060:2) and instance 4098 on both XTRs; MSMR1 sites AST-XTR1/AST-XTR2 each with a 4097 and a 4098 eid-record; BDR1 = F-H's BDR1 without the VN LANs (e0/1, e0/2 shut, no `network` statements), Loopback0 and e0/3 in OSPF 1 area 0, per-VRF eBGP to FUS1. BDR1 has no `router lisp`. DC-FUS1, DC-RTR1, DC-DNS1: as stage FAB F-H, unchanged (prefix-lists still /24).

## Proven (LAB-069 build)
MS registers both XTR sites for both instances; OSPF FULL on SPINE1 (4); BGP Established CORP/IOT with 0 prefixes from Aster, 1 (10.50.51.0/24) from FUS1; CORP-CORP and IOT-IOT work, CORP-IOT fails; fabric hosts cannot reach 10.50.51.53 (negative map-cache entry, action forward-native, then `!H` from the edge). Settling: registrations within about 90 s of boot.
## Files
`FAB-MSMR1.cfg`, `FAB-SPINE1.cfg`, `FAB-XTR1.cfg`, `FAB-XTR2.cfg`, `FAB-BDR1.cfg`, `FAB-PC1.cfg`, `FAB-PC2.cfg` (DC files: F-H).
