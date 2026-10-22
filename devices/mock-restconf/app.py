"""Minimal RESTCONF simulator exposing ietf-interfaces (RFC 8343) over HTTP.

Lab-only: plain HTTP + basic auth. Use a real device (HTTPS) for production.
Fault injection: POST /control?interface=GigabitEthernet0/1&state=down   (state=up|down, interface=all)
"""
import json, os, random, threading, time
from flask import Flask, Response, jsonify, request

NAME = os.getenv("DEVICE_NAME", "edge-router")
USER = os.getenv("RESTCONF_USER", "labuser")
PASSWORD = os.getenv("RESTCONF_PASSWORD", "labpass")

app = Flask(__name__)
lock = threading.Lock()
IFACES = {f"GigabitEthernet0/{i}": {"up": True, "in": 0, "out": 0} for i in range(1, 4)}


def ticker():
    while True:
        time.sleep(1)
        with lock:
            for st in IFACES.values():
                if st["up"]:
                    st["in"] += random.randint(10_000, 500_000)
                    st["out"] += random.randint(10_000, 500_000)


threading.Thread(target=ticker, daemon=True).start()


@app.before_request
def check_auth():
    if request.path.startswith("/restconf"):
        a = request.authorization
        if not (a and a.username == USER and a.password == PASSWORD):
            return Response("Unauthorized", 401, {"WWW-Authenticate": 'Basic realm="restconf"'})


@app.get("/restconf/data/ietf-interfaces:interfaces")
def interfaces():
    with lock:
        items = [{
            "name": n,
            "type": "iana-if-type:ethernetCsmacd",
            "enabled": True,
            "oper-status": "up" if s["up"] else "down",
            "statistics": {"in-octets": s["in"], "out-octets": s["out"]},
        } for n, s in IFACES.items()]
    body = json.dumps({"ietf-interfaces:interfaces": {"interface": items}})
    return Response(body, mimetype="application/yang-data+json")


@app.get("/restconf/data/ietf-system:system")
def system():
    return jsonify({"ietf-system:system": {"hostname": NAME}})


@app.post("/control")
def control():
    name, state = request.args.get("interface"), request.args.get("state")
    if state not in ("up", "down"):
        return jsonify(error="state must be up|down"), 400
    with lock:
        targets = list(IFACES) if name == "all" else [name]
        for t in targets:
            if t not in IFACES:
                return jsonify(error=f"unknown interface {t}"), 404
            IFACES[t]["up"] = state == "up"
    return jsonify(device=NAME, interface=name, state=state)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, threaded=True)
