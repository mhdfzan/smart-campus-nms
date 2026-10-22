#!/usr/bin/env python3
"""JSON helpers for the shell scripts. Reads JSON on stdin. Never raises: prints nothing on bad input."""
import json
import sys
from datetime import datetime


def load():
    try:
        return json.load(sys.stdin)
    except Exception:
        return {}


def to_epoch_ms(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        pass
    try:
        return datetime.fromisoformat(str(v).replace("Z", "+00:00")).timestamp() * 1000
    except Exception:
        return 0.0


def alarms(d):
    a = d.get("alarm", [])
    return [a] if isinstance(a, dict) else a


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    d = load()
    if cmd == "first_value":            # Prometheus instant-query response -> first value
        r = d.get("data", {}).get("result", [])
        print(r[0]["value"][1] if r else "")
    elif cmd == "count_nodes":          # OpenNMS /rest/nodes
        n = d.get("node", [])
        print(1 if isinstance(n, dict) else len(n))
    elif cmd == "node_labels":          # OpenNMS /rest/nodes -> one label per line
        n = d.get("node", [])
        for x in ([n] if isinstance(n, dict) else n):
            print(x.get("label", ""))
    elif cmd == "list_alarms":
        for a in alarms(d):
            msg = " ".join(str(a.get("logMessage", "")).replace("<p>", "").replace("</p>", "").split())
            print(a.get("id"), a.get("severity"), a.get("nodeLabel", "-"), "ack:" + str(a.get("ackUser") or "-"), msg[:80])
    elif cmd == "find_alarm":           # LABEL PAT1|PAT2 SINCE_MS -> newest non-cleared alarm id
        label, pats, since = sys.argv[2], sys.argv[3].split("|"), float(sys.argv[4])
        for a in alarms(d):
            text = str(a.get("uei", "")) + str(a.get("logMessage", ""))
            if (a.get("nodeLabel") == label and any(p in text for p in pats) and a.get("severity") != "CLEARED"
                    and to_epoch_ms(a.get("lastEventTime", 0)) >= since):
                print(a["id"])
                break
    elif cmd == "alarm_field":          # ID FIELD
        for a in alarms(d):
            if str(a.get("id")) == sys.argv[2]:
                print(a.get(sys.argv[3]) or "")
                break


if __name__ == "__main__":
    main()
