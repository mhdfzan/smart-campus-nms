#!/usr/bin/env python3
"""Campus NETCONF/RESTCONF -> Prometheus exporter.

Polls devices listed in devices.yml, normalises ietf-interfaces data and exposes:
  campus_device_up{device,protocol}
  campus_device_scrape_duration_seconds{device}
  campus_device_interface_oper_status{device,interface}      1=up 0=down
  campus_device_interface_in_octets_total / _out_octets_total{device,interface}
"""
import logging, os, time
import xml.etree.ElementTree as ET

import requests
import yaml
from prometheus_client import REGISTRY, start_http_server
from prometheus_client.core import CounterMetricFamily, GaugeMetricFamily

CONFIG = os.getenv("DEVICES_FILE", "devices.yml")
PORT = int(os.getenv("EXPORTER_PORT", "9200"))
log = logging.getLogger("campus-exporter")


# ---------------- RESTCONF ----------------
def fetch_restconf(dev):
    base = dev["url"].rstrip("/")
    hdr = {"Accept": "application/yang-data+json"}
    auth = (dev.get("username"), dev.get("password"))
    verify = dev.get("verify_tls", True)
    for path, root_key, list_key in (
        ("ietf-interfaces:interfaces", "ietf-interfaces:interfaces", "interface"),
        ("ietf-interfaces:interfaces-state", "ietf-interfaces:interfaces-state", "interface"),  # older RFC 7223 devices
    ):
        r = requests.get(f"{base}/restconf/data/{path}", headers=hdr, auth=auth, verify=verify, timeout=10)
        if r.status_code == 404:
            continue
        r.raise_for_status()
        items = r.json().get(root_key, {}).get(list_key, [])
        if items:
            return [{
                "name": i["name"],
                "oper": 1 if i.get("oper-status") == "up" else 0,
                "in": int(i.get("statistics", {}).get("in-octets", 0)),
                "out": int(i.get("statistics", {}).get("out-octets", 0)),
            } for i in items]
    return []


# ---------------- NETCONF ----------------
def _local(tag):
    return tag.rsplit("}", 1)[-1]


def _child_text(el, name):
    for c in el.iter():
        if _local(c.tag) == name and c.text:
            return c.text.strip()
    return None


def parse_netconf_interfaces(xml_text):
    root = ET.fromstring(xml_text)
    out = []
    for el in root.iter():
        if _local(el.tag) == "interface":
            name = next((c.text.strip() for c in el if _local(c.tag) == "name" and c.text), None)
            if not name:
                continue
            status = _child_text(el, "oper-status")
            out.append({
                "name": name,
                "oper": 1 if status == "up" else 0,
                "in": int(_child_text(el, "in-octets") or 0),
                "out": int(_child_text(el, "out-octets") or 0),
            })
    return out


def fetch_netconf(dev):
    from ncclient import manager  # imported lazily so RESTCONF-only setups work
    filters = (
        "<interfaces xmlns='urn:ietf:params:xml:ns:yang:ietf-interfaces'/>",
        "<interfaces-state xmlns='urn:ietf:params:xml:ns:yang:ietf-interfaces'/>",
    )
    with manager.connect(host=dev["host"], port=dev.get("port", 830), username=dev["username"],
                         password=dev["password"], hostkey_verify=dev.get("hostkey_verify", False),
                         device_params={"name": "default"}, allow_agent=False, look_for_keys=False,
                         timeout=15) as m:
        for flt in filters:
            reply = m.get(filter=("subtree", flt))
            items = parse_netconf_interfaces(reply.data_xml)
            if items:
                return items
    return []


FETCHERS = {"restconf": fetch_restconf, "netconf": fetch_netconf}


# ---------------- Collector ----------------
class CampusCollector:
    def collect(self):
        with open(CONFIG) as f:
            devices = (yaml.safe_load(f) or {}).get("devices", [])
        up = GaugeMetricFamily("campus_device_up", "1 if the device answered its management protocol", labels=["device", "protocol"])
        dur = GaugeMetricFamily("campus_device_scrape_duration_seconds", "Poll duration", labels=["device"])
        oper = GaugeMetricFamily("campus_device_interface_oper_status", "Interface operational status (1=up,0=down)", labels=["device", "interface"])
        inb = CounterMetricFamily("campus_device_interface_in_octets", "Octets received", labels=["device", "interface"])
        outb = CounterMetricFamily("campus_device_interface_out_octets", "Octets sent", labels=["device", "interface"])
        for d in devices:
            proto, t0 = d.get("protocol", "restconf"), time.time()
            try:
                ifaces = FETCHERS[proto](d)
                up.add_metric([d["name"], proto], 1)
                for i in ifaces:
                    lbl = [d["name"], i["name"]]
                    oper.add_metric(lbl, i["oper"])
                    inb.add_metric(lbl, i["in"])
                    outb.add_metric(lbl, i["out"])
            except Exception as e:  # device unreachable, auth failure, bad data...
                log.warning("poll of %s failed: %s", d["name"], e)
                up.add_metric([d["name"], proto], 0)
            dur.add_metric([d["name"]], time.time() - t0)
        yield from (up, dur, oper, inb, outb)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    REGISTRY.register(CampusCollector())
    start_http_server(PORT)
    log.info("campus exporter listening on :%d, config=%s", PORT, CONFIG)
    while True:
        time.sleep(3600)
