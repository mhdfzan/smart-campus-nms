# Test plan

For testers who have **not** seen the code. First complete [SETUP.md](SETUP.md) so that `bash scripts/check_stack.sh` shows only `OK`.
Work from the project folder in the Ubuntu terminal. You need a web browser for Part B.

**Goal:** confirm that the system discovers devices, collects SNMP and NETCONF/RESTCONF data, shows it on a dashboard, detects failures, raises alarms and recovers.

## How testing works
1. **Part A: automated tests** (terminal). One command per group; results are saved to `test-results/results-<time>.md`.
2. **Part B: manual visual checks** (browser). Take a screenshot of each.
3. **Part C: manual alarm lifecycle** (browser + terminal).
4. **Part D: optional real NETCONF device.**
5. Fill in the results table at the end and report problems (section "Reporting").

The failure tests deliberately stop containers and then wait (a dot is printed every few seconds, a single test can take up to 5 minutes). **Do not press Ctrl+C while a test is running**: it aborts the run and the interrupted test is reported as FAIL. If you do abort, everything is restored automatically. Do not run two test groups at the same time, and do not touch the services while a test runs.

---

## Part A: automated tests

```bash
bash scripts/run_tests.sh          # A1: basic, about 2 minutes, nothing is broken
bash scripts/run_tests.sh faults   # A2: about 10 minutes
bash scripts/run_tests.sh alarms   # A3: about 5-20 minutes
bash scripts/run_tests.sh full     # everything, plus SNMP outage and CPU load, 30-60 minutes
```
Each line shows `PASS`, `FAIL` or `WARN` (passed with a note). A run is successful when there are no `FAIL`.

| ID | Group | What is checked | Expected |
|---|---|---|---|
| T01 | all | Every endpoint answers (OpenNMS, Prometheus, Grafana, exporters, 2 RESTCONF devices) | all OK |
| T02 | basic | Prometheus scrape targets | all UP |
| T03 | basic | OpenNMS discovered the four campus nodes by name | core-router, switch-admin, switch-academic, dc-server present (an extra OpenNMS self-monitoring node is normal) |
| T04 | basic | SNMP identity of the 4 devices | Cisco, Juniper, Arista, Linux strings |
| T05 | basic | RESTCONF access with valid login | JSON interface data from both routers |
| T06 | basic | RESTCONF without/with wrong login | HTTP 401 both times |
| T07 | basic | Exporter metrics (NETCONF/RESTCONF → Prometheus) | both routers up, 6 interface series |
| T08 | basic | Grafana dashboard exists and can query Prometheus | yes |
| T09 | faults | Interface goes down, `InterfaceDown` alert fires, recovery | metric 0 within ~30 s, alert within ~2 min, then clears |
| T10 | faults | Router stops, `DeviceUnreachable` fires, recovery | same pattern |
| T11 | faults | node-exporter stops, `ExporterTargetDown` fires, recovery | same pattern |
| T12 | alarms | Stopping `switch-admin` creates an OpenNMS alarm | alarm appears (about 1-3 min with fast polling) |
| T13 | alarms | The alarm is acknowledged | acknowledged by `admin` |
| T14 | alarms | Device restored, alarm clears | cleared automatically (WARN if it had to be cleared manually via API) |
| T15 | full | SNMP agent frozen, OpenNMS detects SNMP outage | alarm appears |
| T16 | full | CPU load, `HighCpuUsage` fires, then resolves | yes (takes several minutes) |

If a test fails, run it once more first (timing issues happen). If it fails again, follow "Reporting".

---

## Part B: manual visual checks (browser)

Take a screenshot of every numbered item and name the files `B1.png`, `B2.png`, ...

**B1. OpenNMS nodes.** Open http://localhost:8980/opennms (admin / admin). Left sidebar → **Inventory → Nodes** (or open http://localhost:8980/opennms/element/nodeList.htm).
Expected: the 4 nodes `core-router`, `switch-admin`, `switch-academic`, `dc-server` (you may also see an extra node for the OpenNMS server itself; that is normal).

**B2. Node details.** Click each node.
Expected: description mentions Cisco / Juniper / Arista / Linux; services **ICMP** and **SNMP** are green; availability about 100 %.

**B3. Dashboard.** Open http://localhost:3000/d/campus-overview (admin / campus123), time range *Last 30 minutes*.
Expected: all boxes green **UP**; CPU, memory and traffic graphs have lines; the Disk gauge shows a percentage; "Active Prometheus alerts" is empty.

**B4. Prometheus targets.** Open http://localhost:9090/targets. Expected: `campus-devices`, `campus-linux`, `prometheus` all **UP**.

**B5. Interface failure, visible in Grafana.** Keep the dashboard open next to the terminal.
```bash
bash scripts/demo_failures.sh iface-down
```
Expected: within about 15 seconds the panel *Interface operational status* shows **edge-router-1 GigabitEthernet0/1 DOWN** (red). After about 1 minute the alert **InterfaceDown** appears in the alerts table and at http://localhost:9090/alerts.
```bash
bash scripts/demo_failures.sh iface-up
```
Expected: back to UP and the alert disappears within about 1-2 minutes.

**B6. Router unreachable.** `bash scripts/demo_failures.sh router-down` → *Devices reachable* shows **edge-router-2 DOWN**; alert **DeviceUnreachable**. Recover with `router-up`.

**B7. CPU load.** `bash scripts/demo_failures.sh cpu-load` → CPU panel rises toward 100 %; **HighCpuUsage** alert after a few minutes. Stop with `cpu-stop`.

**B8. Exporter failure.** `bash scripts/demo_failures.sh exporter-down` → *Scrape targets up* shows **campus-linux DOWN**; http://localhost:9090/targets shows it DOWN. Recover with `exporter-up`.

---

## Part C: alarm lifecycle by hand (the key requirement)

Open two browser tabs: the OpenNMS **Alarms** page (http://localhost:8980/opennms/alarm/list.htm) and the Grafana dashboard. Write down the time (`date`) of every step.

1. **Fault.** `date; bash scripts/demo_failures.sh device-down` (stops `switch-admin`).
2. **Detection / alarm created.** Wait 1-3 minutes, refresh the Alarms page. Expected: a new alarm for `switch-admin` (node down / lost service). Screenshot it and note its **ID**.
   Also list it in the terminal: `bash scripts/alarm_lifecycle.sh list`
3. **Acknowledge.** Tick the alarm's checkbox, choose **Acknowledge** in the action menu, click Go. Or: `bash scripts/alarm_lifecycle.sh ack <ID>`. Expected: the alarm shows as acknowledged by admin.
4. **Recovery.** `date; bash scripts/demo_failures.sh device-up`.
5. **Clearance.** Wait 1-3 minutes and refresh. Expected: the alarm severity becomes **Cleared**. If nothing happens after 5 minutes: `bash scripts/alarm_lifecycle.sh clear <ID>` and note that clearance was manual.
6. **Outage record.** Open http://localhost:8980/opennms/outage/index.jsp. Expected: the outage with a start and end time.

Record: fault time, alarm created, acknowledged, restored, cleared. *Detection time* = alarm created − fault. *Resolution time* = cleared − fault.

Optional: `bash scripts/demo_failures.sh snmp-down` freezes the SNMP agent of `switch-academic`. After a few minutes OpenNMS should show an **SNMP** service outage for that node while ICMP stays green. Recover with `snmp-up`.

---

## Part D: optional, real NETCONF device
The RESTCONF routers are simulators. To prove NETCONF against a real device:
1. Create a free account at developer.cisco.com and open the **Always-On IOS XE** sandbox page; note host, NETCONF port (830), username, password.
2. Edit `exporter/devices.yml`: remove the `#` characters from the `cisco-iosxe-sandbox` block (keep the indentation) and fill in the values.
3. `docker compose up -d --build campus-exporter` then `docker compose logs campus-exporter | tail -20`
4. `curl -s localhost:9200/metrics | grep cisco-iosxe-sandbox` → expected `campus_device_up{...} 1.0` and interface lines. Screenshot the Grafana panels.
Never commit real passwords to Git.

---

## Results table (copy and fill in)

| ID | Result (PASS/FAIL/WARN) | Time | Notes / screenshot file |
|---|---|---|---|
| T01-T08 (A1) | | | |
| T09-T11 (A2) | | | |
| T12-T14 (A3) | | | |
| T15-T16 (full) | | | |
| B1-B4 | | | |
| B5 interface failure | | | |
| B6 router unreachable | | | |
| B7 CPU load | | | |
| B8 exporter failure | | | |
| C alarm lifecycle: fault / created / acked / restored / cleared | | | |
| D real NETCONF | | | |

## Reporting a problem
Send the project owner:
1. the test ID and what you expected versus what happened;
2. the file from `test-results/` (it contains times and details);
3. the file created by `bash scripts/collect_logs.sh` (`diagnostics-*.txt`);
4. screenshots.

## Clean reset (if the system is in a strange state)
```bash
docker compose down -v
bash setup.sh
```
