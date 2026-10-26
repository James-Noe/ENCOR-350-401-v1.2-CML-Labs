# AUTO A3 stage (agent, script and orchestration)

Proven by LAB-063.

Built by LAB-063 from A2. Topology, addressing, credentials and the RTR3 certificate behaviour as in `../A0/README.md` and `../A1/README.md`.

**A3 = A2 +**
- **AUTO-RTR1** (`AUTO-RTR1.cfg`): `snmp-server location Veridian AUTO pod`, `snmp-server contact noc@veridian.example`, and EEM applet `STD-WATCH` (`event timer watchdog time 60`; `show running-config | include ^snmp-server location`; `action regexp` + `if $_regexp_result eq 0` re-applies both lines and logs `%HA_EM-6-LOG: STD-WATCH: standard SNMP lines were missing, re-applied`).
- **AUTO-RTR3** (`AUTO-RTR3.cfg`): the same two `snmp-server` lines.
- **AUTO-MGMT1** (`AUTO-MGMT1.user-data`): Ansible 14.4.0 (core 2.21.5, cisco.ios 11.5.1, ansible.netcommon 8.6.2) installed in `/home/cisco/venv` by the same cloud-init `runcmd` as the other venv packages (log `/var/log/a3-venv.log`; needs the NAT connector, about 1 to 2 min after the venv), and `/home/cisco/ansible/` with `ansible.cfg`, `inventory.yml` (routers AUTO-RTR1 10.90.50.1, AUTO-RTR3 10.90.50.11; netconf host alias RTR3-NC), `group_vars/` (network_cli as `admin`; netconf port 830 as `apiuser`; `std_lines`), `std.yml` (`cisco.ios.ios_config`) and `std_netconf.yml` (`netconf_config`, retries on `lock-denied`).

Measured on a cold boot test: both playbooks `changed=0` on the first run (standard already present); the first NETCONF run right after RESTCONF first answered 200 failed once with `command timeout triggered, timeout value is 30 secs` and passed on the next run (cold `netconf-yang`): wait a minute or re-run. `ansible_pylibssh` is not installed; Ansible falls back to paramiko (warning, harmless).

Applet behaviour: the watchdog ticks every 60 s, so a removed line is back 1-65 s later (measured 32.7/41.8/41.8 s). The first tick after boot applies the standard if it is missing. AUTO-RTR3 has no applet by design, so its drift is not corrected by A3 itself.
