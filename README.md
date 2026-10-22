# Smart Campus Network Monitoring System

An open-source network management system for multi-vendor campus networks: **SNMP + NETCONF + RESTCONF** data collection,
**alarm lifecycle management** (detect → alarm → acknowledge → recover → clear) and **observability dashboards**.
Built with **OpenNMS Horizon, Prometheus, Grafana** and a custom Python exporter, running on Ubuntu with Docker Compose.
Course project: *Network Management System – Project 1 (REVA University)*.

```
 Simulated campus (172.28.0.0/24)                        Monitoring server (Docker on Ubuntu)
 ┌────────────────────────────────┐   SNMP / ICMP       ┌───────────────────────────────┐
 │ core-router     .10 (Cisco)    │────────────────────▶│ OpenNMS :8980                 │
 │ switch-admin    .11 (Juniper)  │                     │ discovery · polling · alarms  │
 │ switch-academic .12 (Arista)   │                     └───────────────────────────────┘
 │ dc-server       .13 (Linux)    │
 ├────────────────────────────────┤  RESTCONF / NETCONF ┌──────────────┐ scrape ┌────────────┐   ┌─────────┐
 │ edge-router-1   .20 (RESTCONF) │────────────────────▶│campus-exporter│──────▶│ Prometheus │──▶│ Grafana │
 │ edge-router-2   .21 (RESTCONF) │                     │   :9200       │ node-  │   :9090    │   │  :3000  │
 └────────────────────────────────┘                     └──────────────┘ export. └────────────┘   └─────────┘
```

| Component | Role |
|---|---|
| OpenNMS | device discovery, availability, SNMP polling, events and alarms |
| Prometheus | metric storage and alert rules |
| Grafana | dashboards |
| campus-exporter | reads `ietf-interfaces` data from NETCONF/RESTCONF devices and exposes it as Prometheus metrics |
| Simulated devices | vendor-flavoured SNMP agents and RESTCONF routers with fault injection |

## Quick start

Needs Linux (Ubuntu 22.04/24.04, or Ubuntu on WSL2), Docker, 8 GB RAM. Full instructions: **[docs/SETUP.md](docs/SETUP.md)**.

```bash
git clone <this-repo-url>
cd <repo-folder>
bash setup.sh            # 15-25 minutes the first time
bash scripts/run_tests.sh
```

| Service | URL | Login |
|---|---|---|
| Grafana (dashboard *Smart Campus Network Overview*) | http://localhost:3000 | admin / campus123 |
| OpenNMS | http://localhost:8980/opennms | admin / admin |
| Prometheus | http://localhost:9090 | – |

## Documentation
- **[docs/SETUP.md](docs/SETUP.md)** – install and run from scratch, troubleshooting
- **[docs/TESTING.md](docs/TESTING.md)** – automated and manual test plan with expected results (for testers)
- [docs/REPORT.md](docs/REPORT.md) – project report skeleton

## Useful commands
```bash
bash scripts/check_stack.sh                 # health check
bash scripts/run_tests.sh [basic|faults|alarms|full]
bash scripts/demo_failures.sh <name>        # manual failure injection (run without arguments for the list)
bash scripts/alarm_lifecycle.sh list|ack|clear <id>
bash scripts/collect_logs.sh                # diagnostics bundle for bug reports
docker compose down                         # stop      (add -v to delete all data)
```

## Repository layout
```
setup.sh                one-command setup            exporter/          NETCONF/RESTCONF -> Prometheus exporter
docker-compose.yml      the whole stack              prometheus/        scrape config + alert rules
devices/snmp-device     vendor-flavoured SNMP agent  grafana/           provisioned datasource + dashboard
devices/mock-restconf   RESTCONF simulator           opennms/           provisioning + fast-polling scripts
scripts/                tests, failure demos, helpers  docs/            setup, testing, report
```

## Known limitations
- The Cisco/Juniper/Arista/Linux devices are **simulated** (net-snmp agents with vendor identifiers), and the RESTCONF routers are a simulator. NETCONF has been unit-checked on sample XML; validate it on a real device (e.g. Cisco DevNet Always-On IOS XE sandbox) by enabling the commented block in `exporter/devices.yml`.
- OpenNMS does not natively ingest NETCONF/RESTCONF; that path is exporter → Prometheus → Grafana.
- Lab security only: SNMPv2c `public`, plain HTTP, default passwords. Production: SNMPv3 authPriv, HTTPS, vaulted credentials. Do not expose these ports to the internet.
- Prometheus, Grafana and node-exporter images use `latest`; OpenNMS is pinned (`OPENNMS_VERSION`, default 36.0.5). Pin the others with `docker compose images` once you have a tested set.
- No Alertmanager routing is configured; alerts are viewed in Prometheus and Grafana.

License: MIT.
