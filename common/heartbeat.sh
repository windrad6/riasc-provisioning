#!/bin/bash

set -e

# Helper functions
function config() {
	[ -f ${CONFIG_FILE} ] && yq eval "$@" ${CONFIG_FILE}
}

function log() {
	echo
	echo -e "\e[32m###\e[0m $1"
}

function warn() {
	echo -e "\e[33m#\e[0m $1"
}

function die() {
	echo -e "\e[31m#\e[0m $1"
	exit -1
}

exec 1> >(logger -st "heartbeat") 2>&1

# Find configuration file
if [ -z "${CONFIG_FILE}" ]; then
	for DIR in /boot /boot/firmware /etc .; do
		if [ -f "${DIR}/riasc.yaml" ]; then
			CONFIG_FILE="${DIR}/riasc.yaml"
			break
		fi
	done
fi

# Validate config
log "Validating config file..."
if ! config true > /dev/null; then
	die "Failed to parse config file: ${CONFIG_FILE}"
fi

log "Heartbeat $(date)"


DEVICE_ID=$(config .ansible.device_id)
API_HOST=$(config .ansible.api_host)

UPTIME=$(awk '{print $1}' /proc/uptime)

TS=$(date +%s)
BODY="{\"action\" : \"heartbeat\", \"uptime\" : ${UPTIME}, \"ts\" : ${TS}}"
RES=$(curl --header "Content-Type: application/json" \
    --write-out %{http_code} \
    --request POST \
    --data "$BODY" \
    $API_HOST/telemetry.php?id=$DEVICE_ID \
    )

exit 0
