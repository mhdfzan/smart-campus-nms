#!/bin/sh
# Simulated network device: a net-snmp agent that identifies itself as a given vendor.
cat > /etc/snmp/snmpd.conf <<CONF
agentAddress udp:161
rocommunity ${COMMUNITY:-public} default
sysName ${SYS_NAME:-device}
sysDescr ${SYS_DESCR:-Simulated device}
sysObjectID ${SYS_OID:-.1.3.6.1.4.1.8072.3.2.10}
sysLocation ${SYS_LOCATION:-Campus Lab}
sysContact it-support@campus.example
CONF
exec snmpd -f -Lo -C -c /etc/snmp/snmpd.conf
