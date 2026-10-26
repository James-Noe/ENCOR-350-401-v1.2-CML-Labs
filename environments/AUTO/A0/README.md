# AUTO A0 stage baseline

Proven by LAB-060.

Built by LAB-060. LAB-061 builds A1 from it.

**Profile:** AUTO lite, **4 nodes** (+ the NAT connector, not counted): AUTO-MGMT1 (`ubuntu`), AUTO-RTR1 (`iol-xe`), AUTO-RTR3 (`cat8000v` 17.16.1a, **`cpus: 2`**), AUTO-SW (`unmanaged_switch`, counted).

## Topology and addressing

```
        AUTO-RTR1 e0/0 .1 ----+                         AUTO-RTR1 e0/2 .2 ==== Gi2 .3 AUTO-RTR3
        AUTO-RTR3 Gi1  .11 ---+-- AUTO-SW   10.90.50.0/24      (10.90.255.2/31, OSPF area 0, cost 10)
        AUTO-MGMT1 ens2 .31 --+
        AUTO-MGMT1 ens3 -- NAT connector (DHCP 192.168.255.x, default route)
```

| Link | A | B | Addressing |
|---|---|---|---|
| API segment | AUTO-RTR1 e0/0, AUTO-RTR3 Gi1, AUTO-MGMT1 ens2 (on AUTO-SW) | | 10.90.50.0/24: RTR1 .1, RTR3 .11, MGMT1 .31 (OSPF passive) |
| RTR1-RTR3 | AUTO-RTR1 e0/2 | AUTO-RTR3 Gi2 | 10.90.255.2/31 (RTR1 .2, RTR3 .3) |
| Internet | AUTO-MGMT1 ens3 | NAT | DHCP |

AUTO-MGMT1 static routes (cloud-init network-config on ens2, via 10.90.50.1): 10.90.0.0/16, 10.255.90.0/24 (the pod loopbacks) and 10.50.0.0/16. The 10.50.0.0/16 route is a reserved route toward further lab address space that later AUTO stages and labs may use; nothing in A0 answers on it and no A0 check depends on it.

Loopback0: RTR1 10.255.90.1/32, RTR3 10.255.90.11/32 (OSPF 1 area 0). Credentials: `admin` / `Cisco123!` (priv 15) on the routers, `cisco` / `cisco` on AUTO-MGMT1. Link switch ports: AUTO-SW port0 RTR1, port1 RTR3, port2 MGMT1.

## Content

- Files: `AUTO-RTR1.cfg`, `AUTO-RTR3.cfg` (day-0), `AUTO-MGMT1.user-data` and `AUTO-MGMT1.network-config` (cloud-init; the user-data carries the LAB-059 YANG/JSON/tree material in `/home/cisco/{yang,json,trees}`).
- **AUTO base** (LAB-060's start state, not a stage): the same files with RTR3 `no ip http server`, `no ip http secure-server` and without `netconf-yang`/`restconf`; RTR3 443/830 closed. (The cat8000v enables the HTTPS server by default, so the base needs both `no` lines to keep 443 closed.)
- **A0 = base + on AUTO-RTR3:** `ip http secure-server`, `ip http authentication local`, `netconf-yang`, `restconf`; `no ip http server` stays (80 closed). Loopback100 does not exist. Pre-built AAA on RTR3: `aaa new-model`, `aaa authentication login CON none` (on `line con 0`), `aaa authentication login default local`, `aaa authorization exec default local`.
- AUTO-RTR1: `ntp master 3` (the pod's time source; `sys.peer` check, not "synchronized"), SSH v2 on VTYs.

## Build notes (LAB-060)

1. **AUTO-RTR3 needs `cpus: 2`.** With 1 vCPU, `netconf-yang`/`restconf` never finished starting (`Confd Status: Starting` for over 60 min, HTTP 502 from nginx). Every AUTO stage and lab with a cat8000v (RTR3, RTR4 in A4) keeps `cpus: 2`.
2. **Readiness.** The healthy state lists `confd`, `nesd`, `ndbmand`, `nginx` etc. as `Running` in `show platform software yang-management process`. After a cold boot with the A0 day-0 the first `GET /restconf/data` returns 200 about 4 min after BOOTED (measured in the 1a test with the same lines); enabling at run time on the base takes about 150 s (152 and 153 s). Ports 443 and 830 open, 80 closed.
3. **Every change to RTR3's `line console 0` (some console automation makes one at each connect) starts a DMI sync**; poll readiness from MGMT1 (`curl` GET 200) instead of reconnecting.
4. The self-signed certificate (`IOS-Self-Signed-Certificate-<n>`, RSA 2048, 10 years, no SAN) is created at the first `ip http secure-server`; its number changes per build. A1 replaces it with `TP-RTR3`.
5. RTR1 `Clock is synchronized` takes hours on IOL; do not test it.

## BV outcomes

Start-state checks and RESTCONF/NETCONF measurements are in LAB-060's SOLUTION.md (Verification, Failure / Recovery).
