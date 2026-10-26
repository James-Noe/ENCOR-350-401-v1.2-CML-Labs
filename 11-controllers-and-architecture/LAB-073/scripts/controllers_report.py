#!/usr/bin/env python3
"""Reference solution R5: Manager session -> report/controllers.json -> logout.
TLS: the Manager certificate is self-signed and issued for no name that matches 172.16.0.1,
so verify=False is used. Risk: a man in the middle on VPN0 could read the credentials.
Acceptable only on this isolated pilot VPN; production pins the enterprise root CA."""
import json, sys, requests, urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
BASE = "https://172.16.0.1"
T = 180  # real-time endpoints take 60-120 s
s = requests.Session()
s.verify = False
r = s.post(BASE + "/j_security_check", data={"j_username": "admin", "j_password": sys.argv[1]}, timeout=T)
r.raise_for_status()
if "<html" in r.text.lower():
    raise SystemExit("login failed (HTML login page returned with HTTP %d)" % r.status_code)
tok = s.get(BASE + "/dataservice/client/token", timeout=T)
tok.raise_for_status()
s.headers["X-XSRF-TOKEN"] = tok.text
try:
    devs = s.get(BASE + "/dataservice/device", timeout=T); devs.raise_for_status()
    certs = s.get(BASE + "/dataservice/certificate/vsmart/list", timeout=T); certs.raise_for_status()
    cstate = {(c.get("deviceIP") or c.get("configuredSystemIP")): c.get("state") for c in certs.json()["data"]}
    rows = [{"device": d["host-name"], "personality": d["personality"], "system-ip": d["system-ip"],
             "reachability": d["reachability"], "certificate-state": cstate.get(d["system-ip"], "n/a"),
             "control-connections": d.get("controlConnections")} for d in devs.json()["data"]]
    with open("/home/cisco/sdwan/report/controllers.json", "w") as f:
        json.dump(rows, f, indent=2)
    print(json.dumps(rows, indent=2))
finally:
    s.post(BASE + "/logout", timeout=T, allow_redirects=False)
