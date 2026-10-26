# LAB-063 — Solution

## Summary

Three ways to make the same two lines true on the pod: an on-box agent (EEM watchdog applet on iol-xe), a script (netmiko over SSH, check-then-send), and orchestration (Ansible `cisco.ios.ios_config` over `network_cli`, plus `ansible.netcommon.netconf_config` over NETCONF to the cat8000v). The student measures where the logic runs, what triggers it, what each leaves in the device log and which method notices drift. Blueprint: 6.7 (EEM, Ansible; Implement), 6.6 (agent vs agentless; Recognize), 6.1 (Python and tooling; Perform), 4.6 (NETCONF; Recognize). No intentional faults (I lab). Start state = stage A2; the lab writes stage A3 (`environments/AUTO/A3/`).

## Intentional Faults

None (implementation lab).

## Diagnosis / Methodology

Not a troubleshooting lab. Method: for each approach apply the standard, prove it with `show running-config | include ^snmp-server`, run again, read `show logging | include CONFIG_I` for what the run did, then remove a line by hand and watch.

Behaviour that surprises students (all measured):
- The applet applies the standard by itself on its first tick (the lines are missing at start).
- EEM on iol-xe supports `action regexp` and `if $_regexp_result eq 0` (registered form shows `eq "0"`). The syslog text must not repeat the applet name (the log prefixes `STD-WATCH:`).
- Removal vs applet race (LAB.md R3 warns about it; students who pause between removal and dry run see `changed=0` on RTR1 while RTR3 still shows `changed=1`, because only RTR1 has the applet; the dry run is then correct, not a fault): the watchdog ticks every 60 s, so a manual removal on RTR1 is repaired 1-65 s later. If an Ansible run follows the removal inside that window it shows `changed=1` on RTR1; after more than a minute it shows `changed=0` on RTR1 (the applet got there first).
- `ios_config --check` shows `changed` and, with `-v`, the `commands`, but no diff (Ansible warns it cannot diff against the running config in check mode); `--diff` on a real run prints before/after.
- `netconf_config` needs a `<config>` root (otherwise "content value should have XML string with config tag"), and the `snmp-server` container must carry the native namespace and the `location` leaf the Cisco-IOS-XE-snmp namespace (otherwise `unknown-element snmp-server`).
- A stopped node makes the play report `failed=1 ... timed out`, not `unreachable=1` (paramiko times out after about 15 s; the play continues with the other host).

## Solution Configuration

**AUTO-RTR1** (R1):
```
event manager applet STD-WATCH
 event timer watchdog time 60
 action 1.0 cli command "enable"
 action 1.1 cli command "show running-config | include ^snmp-server location"
 action 1.2 regexp "snmp-server location Veridian AUTO pod" "$_cli_result"
 action 1.3 if $_regexp_result eq 0
 action 1.4 cli command "configure terminal"
 action 1.5 cli command "snmp-server location Veridian AUTO pod"
 action 1.6 cli command "snmp-server contact noc@veridian.example"
 action 1.7 cli command "end"
 action 1.8 syslog msg "standard SNMP lines were missing, re-applied"
 action 1.9 end
```
(Fallback if `action regexp` were missing: drop the `if`, re-apply unconditionally every period; idempotent but one config log line per tick.)

**AUTO-MGMT1, R2** `/home/cisco/push_std.py` (netmiko; checks first, sends only the missing lines, re-verifies):
```python
from netmiko import ConnectHandler

DEVICES = [
    {"device_type": "cisco_ios", "host": "10.90.50.1", "username": "admin", "password": "Cisco123!"},
    {"device_type": "cisco_xe", "host": "10.90.50.11", "username": "admin", "password": "Cisco123!"},
]
STANDARD = ["snmp-server location Veridian AUTO pod", "snmp-server contact noc@veridian.example"]

def main():
    for dev in DEVICES:
        conn = ConnectHandler(**dev)
        have = conn.send_command("show running-config | include ^snmp-server").splitlines()
        missing = [line for line in STANDARD if line not in have]
        if missing:
            conn.send_config_set(missing)
        have = conn.send_command("show running-config | include ^snmp-server").splitlines()
        ok = all(line in have for line in STANDARD)
        print(f"{dev['host']}: sent {len(missing)} line(s), standard present: {ok}")
        conn.disconnect()

if __name__ == "__main__":
    main()
```
Run with `/home/cisco/venv/bin/python push_std.py`.

**AUTO-MGMT1, R3/R4**: `/home/cisco/venv/bin/pip install ansible==14.4.0`, then `/home/cisco/ansible/`:
```
ansible.cfg      [defaults] inventory = inventory.yml / host_key_checking = False / retry_files_enabled = False / interpreter_python = auto_silent
inventory.yml    all > children > routers > hosts AUTO-RTR1 (ansible_host 10.90.50.1), AUTO-RTR3 (10.90.50.11);
                 netconf_hosts > hosts RTR3-NC (ansible_host 10.90.50.11)
group_vars/all.yml            std_lines: [snmp-server location Veridian AUTO pod, snmp-server contact noc@veridian.example]
group_vars/routers.yml        ansible_connection: ansible.netcommon.network_cli, ansible_network_os: cisco.ios.ios, ansible_user: admin, ansible_password: Cisco123!
group_vars/netconf_hosts.yml  ansible_connection: ansible.netcommon.netconf, ansible_network_os: cisco.ios.ios, ansible_port: 830, ansible_user: apiuser, ansible_password: Api#Pass2026
```
`std.yml`:
```yaml
- name: Apply the pod standard over SSH
  hosts: routers
  gather_facts: false
  tasks:
    - name: Standard SNMP lines
      cisco.ios.ios_config:
        lines: "{{ std_lines }}"
        diff_against: running
```
`std_netconf.yml`:
```yaml
- name: Set the SNMP location over NETCONF
  hosts: netconf_hosts
  gather_facts: false
  tasks:
    - name: snmp-server location through the native YANG model
      ansible.netcommon.netconf_config:
        content: |
          <config xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
          <native xmlns="http://cisco.com/ns/yang/Cisco-IOS-XE-native">
            <snmp-server>
              <location xmlns="http://cisco.com/ns/yang/Cisco-IOS-XE-snmp">Veridian AUTO pod</location>
            </snmp-server>
          </native>
          </config>
      register: nc
      retries: 6
      delay: 10
      until: nc is succeeded or 'lock-denied' not in (nc.msg | default(''))
```
Runs: `cd /home/cisco/ansible; /home/cisco/venv/bin/ansible-playbook std.yml --check -v`, then `--diff`, then plain; `ansible-playbook std_netconf.yml`.

## Verification

All outputs captured on a fresh import of the YAML.

**R1/V1/V2** (applet installed at 16:04:39; first tick applied the standard; then a manual `no snmp-server location/contact`):
```
show event manager policy registered
1    applet    user    timer watchdog      Off   Sun Oct 11 16:04:39 2026  STD-WATCH
 time 60.000
 maxrun 20.000
 action 1.3 if $_regexp_result eq "0"
show event manager history events
1    1      Actv success  Sun Oct11 16:05:39 2026  timer watchdog    applet: STD-WATCH
2    2      Actv success  Sun Oct11 16:06:39 2026  timer watchdog    applet: STD-WATCH
show logging | include STD-WATCH|CONFIG_I
*Oct 11 16:05:40.919: %SYS-5-CONFIG_I: Configured from console by  on vty0 (EEM:STD-WATCH)
*Oct 11 16:05:40.924: %HA_EM-6-LOG: STD-WATCH: standard SNMP lines were missing, re-applied
*Oct 11 16:06:41.134: %SYS-5-CONFIG_I: Configured from console by  on vty0 (EEM:STD-WATCH)
```
(While the line is present, events run without a log line.)

**R2/V3** (`push_std.py`, run 1 then run 2; RTR1 already had the lines from the applet):
```
10.90.50.1: sent 0 line(s), standard present: True
10.90.50.11: sent 2 line(s), standard present: True
...
10.90.50.1: sent 0 line(s), standard present: True
10.90.50.11: sent 0 line(s), standard present: True
```
RTR3 `show logging | include CONFIG_I`: one `%SYS-5-CONFIG_I: Configured from console by admin on vty0 (10.90.50.31)` at 16:08:28 after run 1; unchanged after run 2. A naive script that always calls `send_config_set` logs one such line per run on each router (build test).

**R3/V4/V5** (`ansible [core 2.21.5]`, `ansible.netcommon 8.6.2`, `cisco.ios 11.5.1`; standard first removed on both):
```
ansible-playbook std.yml --check -v
changed: [AUTO-RTR3] => {"banners": {}, "changed": true, "commands": ["snmp-server location Veridian AUTO pod", "snmp-server contact noc@veridian.example"], ...}
changed: [AUTO-RTR1] => {... same commands ...}
AUTO-RTR1 : ok=1 changed=1 unreachable=0 failed=0 ...
AUTO-RTR3 : ok=1 changed=1 unreachable=0 failed=0 ...
ansible-playbook std.yml --diff
--- before / +++ after
+snmp-server location Veridian AUTO pod
+snmp-server contact noc@veridian.example
changed: [AUTO-RTR1]   (and the same for AUTO-RTR3)
AUTO-RTR1 : ok=1 changed=1 ...   AUTO-RTR3 : ok=1 changed=1 ...
ansible-playbook std.yml
ok: [AUTO-RTR1]   ok: [AUTO-RTR3]
AUTO-RTR1 : ok=1 changed=0 ...   AUTO-RTR3 : ok=1 changed=0 ...
```
`[WARNING]: ansible-pylibssh not installed, falling back to paramiko` appears; harmless. One task gives `changed=1` per host (`changed=2` across two hosts).

**R4/V6** (RTR3 location removed by CLI first; `apiuser`, port 830):
```
ansible-playbook std_netconf.yml  ->  changed: [RTR3-NC]   RTR3-NC : ok=1 changed=1 ...
RTR3: *Oct 11 16:10:05.136: %DMI-5-CONFIG_I: R0/0: dmiauthd: Configured from NETCONF/RESTCONF by apiuser, transaction-id 127
second run  ->  ok: [RTR3-NC]   changed=0
```
Compare with the SSH push: `%SYS-5-CONFIG_I: Configured from console by admin on vty0 (10.90.50.31)` (source address of the SSH session, VTY); the NETCONF change comes from the DMI subsystem and names the API user and a transaction id, not a VTY or address. `lock-denied` was not reproduced in 3 attempts (NETCONF right after an SSH push and right after a CLI change); the retry stays as a precaution. A cold start gave one `command timeout triggered, timeout value is 30 secs` on the first NETCONF call after RESTCONF first answered; the next call passed.

**R5/V7** (location removed on RTR1 and RTR3, observed 45 s later on RTR1):

| Method | Noticed? | Corrected? | When | Needs |
|---|---|---|---|---|
| EEM applet on RTR1 | yes, each tick | yes | within 1-65 s (watchdog every 60 s) | nothing off the box |
| Script `push_std.py` | only when run | only when run | at the next manual or scheduled run | MGMT1, a scheduler |
| Ansible playbook | only when run | only when run (`changed=1` shows the drift) | at the next run | MGMT1, a scheduler |

RTR3 drift is **not corrected**: RTR3 (cat8000v) carries no applet by design (the stage A3 defines the agent on RTR1 only, so the lab shows that an agent protects only the device it lives on and must be deployed on every device), and nothing runs the script or playbook by itself. After the 45 s wait RTR1 had the line back and RTR3 still lacked it; the next `std.yml` run reported `changed=1` on RTR3 only.

**R6/V8** (RTR1 `write memory` then node stop):
```
changed: [AUTO-RTR3]
fatal: [AUTO-RTR1]: FAILED! => {"changed": false, "msg": "timed out"}
AUTO-RTR1 : ok=0 changed=0 unreachable=0 failed=1 ...
AUTO-RTR3 : ok=1 changed=1 unreachable=0 failed=0 ...
```
After node start (BOOTED in 12 s): startup-config held both `snmp-server` lines and `event manager applet STD-WATCH`; applet registered again at boot; `std.yml` -> `changed=0` on both.

## Failure / Recovery Behaviour

Method: stopping a node is a silent failure (no interface down on the neighbour); removals are done by CLI.

| Scenario (trigger -> end condition) | Runs (raw) | Documented range | Basis |
|---|---|---|---|
| `no snmp-server location` on RTR1 (config block) -> line back on RTR1 (device clock) | 32.7 s, 41.8 s, 41.8 s; 21 s, 27 s, 46 s | 1-65 s | watchdog ticks every 60 s, so repair = uniformly 0-60 s after removal plus 1-2 s run time (not 60-120 s) |
| RTR1 node stop -> `std.yml` ends with `failed=1 "timed out"` | 1 run: about 15 s (15:25:07 -> 15:25:22, build lab; the re-run here ended 16:12:30, start time not recorded) | 10-30 s | paramiko connect timeout; failure is `failed=1`, not `unreachable=1` |
| RTR1 node start -> BOOTED | 13 s, 12 s | 10-20 s | image boot; applet survives because it is in the saved startup config |

Q4 (CPU busy) was not measured; it is answered from the EEM design (below). The applet survives a node stop only if the configuration was saved first.

## Answers to Analysis Questions

- **Q1** Applet: logic on the device; trigger = timer event; transport = local (CLI inside the router), no credentials leave the box (runs as the EEM user, privilege 15); scales by being installed per device; detects drift every tick, repairs it itself; needs EEM on the device; failure visible only in the device log/`history events`. Script: logic on MGMT1; trigger = a person or cron; SSH 22 with `admin`/`Cisco123!` stored in the script; scales by loop (serial, slow); notices drift only when run, fixes it with the next run; needs only SSH; failure = Python exception/printed result. Playbook: logic on MGMT1; trigger = a person/scheduler; SSH 22 (network_cli) or NETCONF 830 with credentials in `group_vars` (vault in production); scales by inventory and parallel forks; drift shows as `changed>0`; needs only SSH/NETCONF; failure = per-host `failed`/`unreachable` in the recap.
- **Q2** A pull-based agent (Puppet/Chef style) runs on the device, polls a server for desired state and so needs the device to reach the controller (outbound), with the controller never needing a path in; EEM's agent is local and event-driven (timer here, syslog/CLI/SNMP events elsewhere) and needs no controller at all; Ansible pushes from the controller and needs the controller to reach every device (SSH/NETCONF) with credentials.
- **Q3** A scheduled job runs forever; if each run re-sends config it floods the log and change records, can disturb state (resets, counters, session churn) and hides real changes. `push_std.py` was idempotent because it reads the lines first and sends only the missing ones (run 2: 0 lines sent, no new `%SYS-5-CONFIG_I`); an always-send script logs a config event per run per router even when nothing changes. `ios_config` is idempotent the same way (it diffs against the running config; `changed=0`).
- **Q4** MGMT1 down: the applet is unaffected (it is on the device), the script and the playbook do not run at all, so drift is not corrected and nothing alerts. RTR1 busy (reasoned, not measured): the watchdog event is delayed or skipped when the EEM server cannot run it (the applet has `maxrun 20`), so repair is late; the script/playbook would also be slow and may time out.
- **Q5** (a) one-off audit of 500 devices: the script or a playbook (`--check`), because nothing has to be installed on the devices and it runs once; (b) a self-healing guard on one device: the EEM applet, because it acts within one period with no external system; (c) a standard on every device for years: Ansible (inventory as source of truth, `changed` shows drift, idempotent, scheduled runs), perhaps with a local guard on critical lines.
- **Q6** Check mode printed `changed` and, with `-v`, the `commands` it would send, but not the before/after diff: Ansible warns it cannot diff against the running config in check mode. The diff is produced by a real run with `diff_against: running` and `--diff`.
- **Q7** The applet checks every 60 s and the playbook runs on demand; if a person removes the lines and runs the playbook within that minute, the playbook sets them (`changed=1`), and the applet's next tick finds them (no action); if the applet fires first, the playbook reports `changed=0`. Either order ends in the same state because both are idempotent. The SSH change is logged as `%SYS-5-CONFIG_I ... by admin on vty0 (<MGMT1 address>)`; the NETCONF change goes through the DMI daemon and is logged as `%DMI-5-CONFIG_I ... by apiuser, transaction-id N` with no VTY, since NETCONF is not a CLI session.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-17 |
| CML | 2.10.0 |
| Node types | cat8000v (IOS XE 17.16.1a), external_connector, iol-xe (IOS XE 17.16.1a), ubuntu (Ubuntu 24.04), unmanaged_switch |
