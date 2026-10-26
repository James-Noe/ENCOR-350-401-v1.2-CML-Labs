# AUTO A1 stage (model-driven change)

Proven by LAB-061.

Built by LAB-061 from A0. Topology, addressing and credentials as in `../A0/README.md`.

**A1 = A0 + on AUTO-RTR3** (day-0 file `AUTO-RTR3.cfg`): `username apiuser privilege 15` (secret `Api#Pass2026`), `ip access-list standard API-CLIENTS` (permit 10.90.50.31 only) applied with `ip http access-class ipv4 API-CLIENTS`, `ip http max-connections 5` (HTTP on port 80 stays off), Loopback101 10.255.90.101/32 advertised by `network 10.255.90.101 0.0.0.0 area 0` (RTR1 learns it), `ntp server 10.255.90.1`, `ip route 10.99.0.0 255.255.0.0 Null0`, description on Gi1 only (the Gi2 description was added and deleted in the lab).

**Certificate (not in day-0).** A cat8000v deletes a day-0 `crypto pki trustpoint` at boot (`%PKI-2-NON_AUTHORITATIVE_CLOCK`, then `TRUSTPOINT_DELETE`), the HTTPS server creates its own `TP-self-signed-<n>` certificate (no SAN), and a dangling `ip http secure-trustpoint` breaks TLS. So `AUTO-MGMT1.user-data` carries `/home/cisco/trust/fetch-rtr3-cert.sh`, started by cloud-init: it waits for the router, then over SSH (`admin`) creates trustpoint `API-TP` (self-signed, CN and subject-alternative-name `rtr3.auto.veridian.example`), sets `ip http secure-trustpoint API-TP`, removes the default trustpoint, runs `crypto pki enroll API-TP`, and stores the certificate the router presents as `/home/cisco/trust/rtr3.pem`. MGMT1 `/etc/hosts` gets `10.90.50.11 rtr3.auto.veridian.example` (cloud-init `runcmd`). Measured on a cold start: file present about 4 min after the nodes are BOOTED, and RESTCONF answers 200 with `curl --cacert /home/cisco/trust/rtr3.pem` a few seconds later (502/000 while the DMI starts).

Files: `AUTO-RTR1.cfg` (= A0), `AUTO-RTR3.cfg`, `AUTO-MGMT1.user-data`, `AUTO-MGMT1.network-config` (= A0). `write_files` under `/home/cisco` makes the home root-owned; any lab built from A1 adds `chown cisco:cisco /home/cisco` (as A2 does). The running RTR3 key pair and certificate differ on every boot; `rtr3.pem` is always fetched from the router, never shipped.
