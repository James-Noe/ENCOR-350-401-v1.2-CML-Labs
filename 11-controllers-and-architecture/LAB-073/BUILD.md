# LAB-073 BUILD.md - recorded `csdwan` build (no YAML)

This lab has no YAML to import (CML cannot re-import an exported SD-WAN lab), so you build it from scratch with this procedure. Tested with: CML 2.10.0, csdwan 3.2.1, SD-WAN 20.16.1.

## 0. Preconditions
```
csdwan --version                # 3.2.1
csdwan images list              # manager/controller/validator 20.16.1 (edge 17.16.01a, unused)
```
The `csdwan setup` node definitions (`Cat SD-WAN <role> (csdwan)`) must still be on the server. If the definitions or images are gone, re-running `csdwan setup` is a server-side change: do it only if you administer the CML server.
No other lab may hold PATty port 7443 (`tools/cml-rest.sh labs`; stop any other SD-WAN lab first). Check `tools/cml-rest.sh budget`: the lab needs 10 running nodes and runs alone.

## 1. Deploy
```
export CML_IP=$CML_HOST CML_USER=$CML_USERNAME      # csdwan reads CML_IP/CML_USER; CML_PASSWORD is shared
export MANAGER_PASSWORD='EncorSdwan#2026'
csdwan -v deploy 20.16.1 --lab "ENCOR LAB-073 SD-WAN Pilot" --manager-port 7443 --manager-user admin </dev/null
```
- Reference run: started 18:31:58, "Deploy complete" about 41 min later, first attempt, no `--retry`. Lab converged after about 4 min, Manager login after about 28 min (Manager boot about 24 min), certificates + serial file + basic configuration + `edge_basic` configuration group about 12 min.
- Second reference run: started 00:27:37, finished about 54 min later, first attempt, no retry; Manager login took longer than the 28 min above. Plan the pre-session deploy for 40-55 min.
- Retry rule: if the Manager API times out (ReadTimeout), wait until five consecutive API answers are fast (a few seconds each), then re-run with `--retry`. The title with spaces was accepted; fallback title `ENCOR-LAB-073-SDWAN` if the tool refuses them.
- Result: 7 licensed nodes (Manager01, Validator01, Controller01, Gateway, INET, MPLS, VPN0 unmanaged switch) plus the `Internet` and `External` connectors = 9 running, plus SDW-MGMT1 below = 10.

## 2. Add SDW-MGMT1
```
SDWAN_LAB="ENCOR LAB-073 SD-WAN Pilot" "$(uv tool dir)/catalyst-sdwan-lab/bin/python" scripts/add_mgmt.py
```
`scripts/add_mgmt.py` creates an `ubuntu` node on a free VPN0 port with a static `network-config` (ens2 172.16.0.50/24, no gateway, no NAT) and cloud-init user-data (`cisco`/`cisco`, `/home/cisco/sdwan/README.txt` and an empty `report/`). The user must be set through `system_info.default_user.name: cisco`; `users: - default` creates `ubuntu` instead. python3 + `requests` 2.31.0 come from the image. Wait with `tools/cml-rest.sh wait "ENCOR LAB-073 SD-WAN Pilot"`.

## 3. Post-deploy checks
1. Run the checks in `scripts/start-checks.cli` on the nodes it names (README + empty `report/`, requests present, 172.16.0.50/24, login page 200, `j_security_check` 200, token fetched).
2. Manager API (https://172.16.0.1 from SDW-MGMT1, or https://<CML host>:7443 from outside), `admin` / `EncorSdwan#2026`:
   - `GET /dataservice/device` lists Manager01 (vmanage 100.0.0.1), Controller01 (vsmart 100.0.0.101), Validator01 (vbond 100.0.0.201), all `reachable`, 20.16.1, site 100.
   - `GET /dataservice/device/control/connections?deviceId=100.0.0.101` returns 3 rows, `.../deviceId=100.0.0.1` 2 rows; `GET /dataservice/device/orchestrator/connections?deviceId=100.0.0.201` returns 10 rows.
   - `GET /dataservice/system/device/vedges` returns 30 serial-file rows (`tokengenerated`, `valid`).
3. Do not leave `controllers.json` or helper scripts on SDW-MGMT1 (`/home/cisco/sdwan/report/` must be empty).

## 4. Helper files
- `scripts/add_mgmt.py`: step 2. `scripts/controllers_report.py`: R5 reference solution. `scripts/start-checks.cli`: step 3.1.
- Note the student can change nothing that breaks the start state: R4 and R5 only create and log out API sessions. The Controller01 stop test (Q5) is reversible with a node start.
