# FAB F3 stage (two-VN fabric with LISP border and fusion handoff; LAB-069 solved state)
Proven by LAB-069 and LAB-071.
Built by LAB-069 from its proven solution (cold-boot tested; passes the end checks). Profile as F1: 10 nodes. F2 = these FAB configs without the DC ones (FUS1's prefix-list change is the only DC difference from F-H).
## Content
F1 plus: FAB-BDR1 `router lisp` with `proxy-etr`, `proxy-itr 10.255.60.21` (no `itr`), `map-cache <VN /23> map-request` in instances 4097/4098, `ip route vrf CORP|IOT <VN /23> Null0` and BGP `network <VN /23>` per VRF; FAB-XTR1/XTR2 `use-petr 10.255.60.21`; DC-FUS1 prefix-lists CORP-USERS 10.60.10.0/23 le 24, IOT-USERS 10.60.20.0/23 le 24 (rest = F-H). DC-RTR1, DC-DNS1 and the PC configs as F-H/F1.
## Proven
PC1 and PC2 reach 10.50.51.53 and resolve erp.veridian.example; CORP-IOT, and 10.50.52.0/24, unreachable. Packets leave the edge LISP-encapsulated toward 10.255.60.21 (UDP 4341, iid 4097/4098) and return encapsulated from BDR1. Settling: first DNS answer 94 s after starting the four changed nodes.
## Files
FAB-MSMR1/SPINE1/XTR1/XTR2/BDR1/PC1/PC2 `.cfg`, DC-FUS1/DC-RTR1 `.cfg`, DC-DNS1 `.boot.sh`/`.dnsmasq.conf`/`.hosts`.
