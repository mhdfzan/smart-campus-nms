Files in this folder are copied into OpenNMS's /opt/opennms/etc at container start.
This placeholder must stay: the OpenNMS image fails to start if the folder only contains hidden files.
bash opennms/fast-polling.sh adds poller-configuration.xml here (generated, not tracked by Git).
