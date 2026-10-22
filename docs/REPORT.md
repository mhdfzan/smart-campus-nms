# Smart Campus Network Monitoring System
**Course:** Network Management System, REVA University | **Student(s):** ______ | **Guide:** Dr. Afifa Salsabil Fathima A | **Date:** ______

## 1. Abstract
University IT staff manage equipment from several vendors with separate tools, which delays fault detection and hides overall network health. This project builds an open-source network management system that integrates SNMP, NETCONF and RESTCONF data, manages alarms through their lifecycle, and provides observability dashboards. The prototype uses OpenNMS, Prometheus and Grafana on Ubuntu, simulated multi-vendor devices, and a custom exporter that converts YANG-model data into Prometheus metrics.

## 2. Problem statement and objectives
Multi-vendor monitoring is fragmented. Objectives: O1 discover and monitor devices from different vendors; O2 integrate SNMP, NETCONF and RESTCONF; O3 detect faults and manage the alarm lifecycle; O4 provide unified dashboards; O5 use open-source tools on Ubuntu; O6 validate with failure/recovery tests.

## 3. Background
- SNMP (RFC 3411-3418): polling of MIB objects (sysDescr, ifTable, counters); v2c community vs v3 authPriv.
- NETCONF (RFC 6241): XML RPCs over SSH (port 830), datastores, YANG models.
- RESTCONF (RFC 8040): HTTP(S) access to YANG data in JSON or XML.
- ietf-interfaces (RFC 8343): vendor-neutral interface model enabling multi-vendor normalisation.
- FCAPS fault management; alarm lifecycle: detection, creation, acknowledgement, resolution, clearance.

## 4. Tool comparison
| Tool | Strengths | Limitation here |
|---|---|---|
| OpenNMS | discovery, SNMP, events and alarms | no native NETCONF/RESTCONF device monitoring |
| Prometheus | metrics, alert rules, exporters | no discovery, no ack/clear alarm lifecycle |
| Grafana | dashboards over many sources | not a collector |
| Zabbix / LibreNMS / Nagios | alternatives | (add your own comparison) |

## 5. System design
Insert the architecture diagram from README.md. Explain the monitoring server, simulated campus (core, admin block, academic block, data centre), data flows (SNMP/ICMP → OpenNMS; NETCONF/RESTCONF → exporter → Prometheus → Grafana) and the decision to split responsibilities between OpenNMS and Prometheus to avoid duplicate collection.
Addressing: 172.28.0.0/24; .10 core-router, .11 switch-admin, .12 switch-academic, .13 dc-server, .20/.21 edge routers.

## 6. Implementation
6.1 Environment (Ubuntu 24.04, Docker Compose). 6.2 Simulated devices (sysObjectIDs: Cisco 1.3.6.1.4.1.9, Juniper ...2636, Arista ...30065). 6.3 OpenNMS provisioning via REST requisition. 6.4 Prometheus scrape jobs and alert rules. 6.5 Exporter: collector pattern, RESTCONF and NETCONF fetchers, metric names, failure handling (`campus_device_up=0`). 6.6 Grafana provisioning and panels. 6.7 Fault-injection tooling.
Include snippets of docker-compose.yml, the exporter collector, one alert rule and the dashboard.

## 7. Testing and results
Paste the completed tables from docs/TESTING.md with screenshots (OpenNMS nodes, alarms before/after acknowledgement, Grafana healthy vs faulted, Prometheus alerts firing) and measured detection and recovery times.

## 8. Discussion
Map O1-O6 to tests. Limitations: simulated vendors, polling latency, no native NETCONF in OpenNMS, lab-grade security. Security: SNMPv3, TLS, read-only least-privilege accounts, secret management, management-plane segmentation.

## 9. Conclusion and future work
Real vendor images in GNS3/containerlab, gNMI streaming telemetry, Alertmanager to email/Slack, topology maps, SNMPv3, NETCONF edit-config for configuration backup, role-based access.

## References
RFC 6241, RFC 8040, RFC 8343, RFC 3411; OpenNMS Horizon, Prometheus and Grafana documentation; Cisco DevNet sandbox documentation.
