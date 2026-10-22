FROM alpine:3.20
RUN apk add --no-cache net-snmp net-snmp-tools
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 161/udp
ENTRYPOINT ["/entrypoint.sh"]
