# LAB-022 — Solution

## Summary

Educational intent: first BGP lab. Students build eBGP to two providers and iBGP to a second enterprise router, read the FSM and logs, learn the exact-match `network` rule and `next-hop-self`, and walk the best-path order by moving a decision with weight, local preference, MED (not compared across neighbouring ASes unless `always-compare-med`) and AS-path prepend, then filter inbound with a prefix-list in a route-map. Blueprint: 3.2.c:I, SK-RM:P. No intentional faults. Platform: iol-xe 17.16.1a (R1-R4), alpine, unmanaged switch INET.

### Build notes

1. `network 10.0.10.0 mask 255.255.0.0` is rejected by IOS (`% BGP: Incorrect network or mask/prefix-length configured`); the lab uses `network 10.0.0.0 mask 255.255.0.0` (accepted, nothing announced).
2. Missing `update-source` on both ends gives state Idle (Up/Down `never`), no log line and no outgoing TCP attempt, not Active/Idle cycling; one end with `update-source` is enough to bring the session up, so the "before" step needs both ends without it. LAB.md asks for the state and the log line.
3. Both providers also announce the Internet LAN 10.0.100.0/24 so PC1 to SRV1 works and shows the exit.
4. The MED step uses an inbound `set metric 100` on R2's path (R2's MED 0 would otherwise win either way).
5. `bgp bestpath compare-routerid` is an R1 requirement (otherwise the eBGP oldest-path rule makes ties history-dependent).

Other notes: provider sessions to R1 carry MD5 passwords (module rule 9); R2-R3 eBGP has none; R3 sets MED 50 on 10.0.201.0/24 towards R1. R1 must not become a transit AS between R2 and R3: the solution filters outbound on both sessions (R6). Providers log `%TCP-6-BADAUTH No MD5 digest` every few seconds until R1 has BGP.

## Intentional Faults

None. The missing `update-source` and `network 10.0.0.0/16` steps are guided misconfigurations.

## Diagnosis / Methodology

- Session state: `show bgp ipv4 unicast summary` (State/PfxRcd, Up/Down) and `show logging | include BGP|TCP`. Wrong remote-as: `%BGP-3-NOTIFICATION ... 2/2 (peer in wrong AS)`. Password mismatch: provider logs `%TCP-6-BADAUTH: No MD5 digest` / `Invalid MD5 digest`, R1 state Active, no ADJCHANGE.
- iBGP without `update-source`: Idle, `never`, 0 messages, `show tcp brief all` only a LISTEN on 179 (no outgoing attempt).
- After `update-source`: Established but R4 shows next hops 10.0.12.2/10.0.13.3 `(inaccessible)`, `* i`, empty `show ip route bgp`: R4 has no route to the eBGP link subnets; `next-hop-self` on R1 fixes it.
- Best path: `show bgp ipv4 unicast 10.0.201.0` on R1 and R4; read the `best` flag and the attribute lines.

## Solution Configuration

R1 (final, as tested):

```
ip prefix-list PL-201 seq 5 permit 10.0.201.0/24
ip prefix-list PL-DOC seq 5 permit 10.0.100.0/24
ip prefix-list PL-DOC seq 10 permit 10.0.200.0/24
ip prefix-list PL-DOC seq 15 permit 10.0.201.0/24
ip prefix-list PL-DOC seq 20 permit 10.0.203.0/24
ip as-path access-list 10 permit ^$
route-map FROM-R2 permit 10
 match ip address prefix-list PL-201
route-map FROM-R2 permit 20
 match ip address prefix-list PL-DOC
route-map FROM-R3 permit 10
 match ip address prefix-list PL-201
route-map FROM-R3 permit 20
 match ip address prefix-list PL-DOC
route-map TO-R2 permit 10
 match as-path 10
route-map TO-R3 permit 10
 match as-path 10
router bgp 65010
 bgp router-id 10.255.0.1
 bgp log-neighbor-changes
 bgp bestpath compare-routerid
 neighbor 10.0.12.2 remote-as 64601
 neighbor 10.0.12.2 password ISPA-64601
 neighbor 10.0.13.3 remote-as 64602
 neighbor 10.0.13.3 password ISPB-64602
 neighbor 10.255.0.4 remote-as 65010
 neighbor 10.255.0.4 update-source Loopback0
 address-family ipv4
  no network 10.0.0.0 mask 255.255.0.0
  network 10.0.10.0 mask 255.255.255.0
  neighbor 10.0.12.2 activate
  neighbor 10.0.12.2 route-map FROM-R2 in
  neighbor 10.0.12.2 route-map TO-R2 out
  neighbor 10.0.13.3 activate
  neighbor 10.0.13.3 route-map FROM-R3 in
  neighbor 10.0.13.3 route-map TO-R3 out
  neighbor 10.255.0.4 activate
  neighbor 10.255.0.4 next-hop-self
```

(The router-id line and prefix-list/route-map names are as built; the `10.0.12.0/24` route is dropped by the implicit deny.)

**Why outbound filters (R6).** An eBGP speaker re-advertises every best path to every eBGP neighbour unless told otherwise. With no outbound policy (or with a route-map whose only clause is an empty `permit 20`, which matches everything), R1 passed R2's routes to R3 and R3's to R2, so each provider saw `65010 64601` / `65010 64602` paths and could send transit traffic through the enterprise. The edge rule is to announce only locally originated prefixes: `^$` matches an empty AS path, which is true only for routes R1 originates (the `network` statement); anything learned from a provider carries that provider's AS. `TO-R2` and `TO-R3` use it. The (d) prepend step is a `set` in the `TO-R3 permit 10` clause, which still matches the originated 10.0.10.0/24.

R4:

```
router bgp 65010
 neighbor 10.255.0.1 remote-as 65010
 neighbor 10.255.0.1 update-source Loopback0
 address-family ipv4
  neighbor 10.255.0.1 activate
```

Temporary best-path steps (each followed by `clear ip bgp <nbr> soft in` or `clear ip bgp * soft`; remove afterwards with the `no` forms below):

- (a) `FROM-R3 permit 10`: `set weight 200`.
- (b) `FROM-R3 permit 10`: `set local-preference 200`.
- (c) `FROM-R2 permit 10`: `set metric 100`; then `router bgp 65010` / `bgp always-compare-med`, `clear ip bgp * soft`; revert with `no bgp always-compare-med` + `clear ip bgp * soft`.
- (d) `TO-R3 permit 10`: `set as-path prepend 65010` (one) then `65010 65010` (two).

Removal forms (route-map sequence in each case, then `clear ip bgp * soft`; the change takes about 15 s to show): (a) `no set weight 200`; (b) `no set local-preference 200`; (c) `no set metric 100`; (d) `no set as-path prepend 65010 65010` (`no set as-path prepend` alone is `% Incomplete` and leaves the prepend). The `no network 10.0.0.0 mask 255.255.0.0` line in the final R1 configuration above removes the guided-misconfiguration `network` statement; without it both `network` lines stay.

## Verification

Captured on iol-xe 17.16.1a:

- Wrong remote-as (R1 configured 64602 for R2): `%BGP-3-NOTIFICATION: sent to neighbor 10.0.12.2 active 2/2 (peer in wrong AS) 2 bytes FC59`; R2 `received from neighbor 10.0.12.1 passive 2/2 (peer in wrong AS)`.
- Password mismatch on R3: `%TCP-6-BADAUTH: No MD5 digest from 10.0.13.1(179) to 10.0.13.3(34844) (RST)` (missing) and `Invalid MD5 digest from 10.0.13.1(55300) to 10.0.13.3(179)` (wrong); R1 state Active.
- iBGP without `update-source` (both ends): R1/R4 State `Idle`, Up/Down `never`, 0 msgs, no log line. With it: `%BGP-5-ADJCHANGE: neighbor 10.255.0.4 Up`; R4 next hops 10.0.12.2/10.0.13.3 `(inaccessible)`. After `next-hop-self` and `clear ip bgp 10.255.0.4 soft out`: R4 `*>i`, next hop 10.255.0.1, `B ... [200/0] via 10.255.0.1`.
- `network 10.0.0.0 mask 255.255.0.0`: `show bgp ipv4 unicast 10.0.0.0/16` gives `% Network not in table`. With `network 10.0.10.0 mask 255.255.255.0`: R2/R3 see 10.0.10.0/24 with path 65010 (and `64602 65010` / `64601 65010` via each other).
- Default best path for 10.0.201.0 on R1: via R2 (metric 0, lower router ID; R3's metric 50 ignored, different AS). R4 sees one path (R1's best, `10.255.0.1 (metric 11)`).
- (a) weight 200 on the R3 path: R1 best via 64602; R4 follows (R4 shows metric 50, localpref 100: weight is local to R1); PC1 `traceroute 10.0.201.1` hop 2 = 10.0.13.3.
- (b) local-preference 200: R1 best 64602 localpref 200; R4 `localpref 200 ... internal, best`.
- (c) metric 100 on R2's path: R1 still best via R2; `bgp always-compare-med` changed nothing until `clear ip bgp * soft`, then best = R3 (metric 50), R4 follows, traceroute hop 2 = 10.0.13.3. After removing: R2 again.
- (d) one prepend towards R3: R3 shows `64601 65010` and `65010 65010`, best = `65010 65010` (tie on length, later tie-breakers decide); two prepends: best `64601 65010`, `65010 65010 65010` second; `traceroute 10.0.10.101 source Loopback2` on R3: 10.0.23.2, 10.0.12.1, 10.0.10.101.
- R6 outbound (proved on a fresh import with this solution): `show bgp ipv4 unicast neighbors 10.0.12.2 advertised-routes` and `... 10.0.13.3 ...` each list only `10.0.10.0/24` (`Total number of prefixes 1`); R2 and R3 hold 10.0.10.0/24 only as `65010` (direct) and via each other (`64602 65010` / `64601 65010`, the providers' own peering), never `65010 6460x`; R4 has the same five routes.
- R5 filter: R1 PfxRcd 4 from each provider, 10.0.12.0/24 absent; R4 table has 5 routes; PC1 ping 10.0.100.200 ok; traceroute PC1 to 10.0.100.200: 10.0.10.1, 10.0.12.2, 10.0.100.200; SRV1 to PC1: 10.0.100.2, 10.0.12.1, 10.0.10.101.

## Failure / Recovery Behaviour

- Cable pull (`shutdown` on both R1 e0/0 and R2 e0/0): `%BGP-5-ADJCHANGE: neighbor 10.0.12.2 Down Interface flap` in the same second (fast external fallover); 10.0.201.0 best moves to R3 (64602), R4 follows, PC1 to 10.0.100.200 goes via 10.0.13.3. After `no shutdown` on both, Established within 45 s, best back to R2.
- Silent failure (CML link stop on R1-R2): interface stays up/up; Down (`BGP Notification sent`, hold timer) about 163 s after the stop in one run (hold time 180 s counted from the last keepalive); in a second run 20 s after the stop the session was still Established and PC1's pings to 10.0.100.200 were 100% lost (black hole); after expiry PC1 reached SRV1 via R3. After link start the session came back within about 3 minutes.

## Answers to Analysis Questions

**Q1** Idle, Up/Down `never`, 0 messages, no log line (no ADJCHANGE, no NOTIFICATION). The session is never opened: observed that R1 makes no outgoing TCP attempt (only a LISTEN on 179). What is proven: a router opens or accepts a session only for the neighbour address it is configured with, and `update-source Loopback0` is what makes a session between loopbacks usable; one end with it is enough to bring the session up. The reason the session sits in Idle without any outgoing attempt (rather than cycling Active/Idle) was not established on the bench and is not claimed here.
**Q2** Weight is Cisco-local: it is not carried in BGP updates, so R4 never sees it; R4 only follows what R1 advertises as best.
**Q3** AS path (including prepends) and MED travel to the neighbouring AS (MED only one AS deep, and not compared across different neighbouring ASes by default); local preference travels only in iBGP inside the AS; weight never leaves the router.
**Q4** `network` originates a prefix only if an exact prefix/mask match is in the RIB (any source). For a /26 not used internally, add a static route to Null0 for that /26, then the `network` statement.
**Q5** `r` = RIB failure: BGP has the route (here best) but the RIB did not install it because the connected route (AD 0) beats eBGP (AD 20). Forwarding is unaffected (the connected route is used); the route is still advertised as a BGP best path.

## Lab Info

| Item | Value |
|---|---|
| Last modified | 2026-10-14 |
| CML | 2.10.0 |
| Node types | alpine (Alpine 3.21.3), iol-xe (IOS XE 17.16.1a), unmanaged_switch |
