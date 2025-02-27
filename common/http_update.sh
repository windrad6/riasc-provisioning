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

# TTY handling
FG_TTY=$(fgconsole || echo 0)
TTY=$(tty | sed -n "s|/dev/tty\(.*\)|\1|p")
if [ -n "${TTY}" ] && (( ${FG_TTY} != ${TTY} )); then
	chvt ${TTY}
	reset
fi

# Tee output to syslog
exec 1> >(logger -st "http-update") 2>&1

# Detect distro
if [ -f /etc/os-release ]; then # freedesktop.org and systemd
	. /etc/os-release
	OS=$NAME
	VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then # linuxbase.org
	OS=$(lsb_release -si)
	VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then # For some versions of Debian/Ubuntu without lsb_release command
	. /etc/lsb-release
	OS=${DISTRIB_ID}
	VER=${DISTRIB_RELEASE}
else
	die "Failed to determine Linux distribution"
fi

# Detect architecture
case $(uname -m) in
	aarch64) ARCH="arm64" ;;
	armv*)   ARCH="arm" ;;
	x86_64)  ARCH="amd64" ;;
esac

# Wait for internet connectivity
log "Wait for internet connectivity"
SERVER="https://github.com"
TRIES=60
TIMEOUT=10 # seconds
while (( TRIES-- > 0 )) && ! wget --timeout=${TIMEOUT} --no-check-certificate --quiet --output-document=/dev/null ${SERVER}; do
    echo "Waiting for network... ${TRIES} tries left.."
    sleep 1
done
if (( COUNTER == TIMEOUT )); then
	die "Failed to get internet connectivity. Aborting"
fi

# Force time-sync via HTTP if NTP time-sync fails
if ! timeout 10 /usr/lib/systemd/systemd-time-wait-sync 2&>1 > /dev/null; then
	log "Falling back to HTTP time-synchronization as NTP is broken"
	date -s "$(curl -s --head http://google.com | grep ^Date: | sed 's/Date: //g')"
fi

# Installing yq
if ! command -v yq &> /dev/null; then
	log "Installing yq"

	YQ_BINARY="yq_linux_${ARCH}"
	YQ_VERSION="v4.7.0"
	YQ_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}"

	wget --quiet ${YQ_URL}
	chmod +x ${YQ_BINARY}
	mv ${YQ_BINARY} /usr/local/bin/yq
fi

# Installing required packages
log "Installing required packages"
if ! command -v unzip &> /dev/null; then
	case ${OS} in
		Fedora|CentOS|'Red Hat Enterprise Linux')
			yum --quiet --yes install unzip
			;;

		Debian|Ubuntu|'Raspbian GNU/Linux')
			apt-get -qq update
			apt-get -qq install unzip
			;;
	esac
fi

if ! command -v ansible &> /dev/null; then
	case ${OS} in
		Fedora|CentOS|'Red Hat Enterprise Linux')
			yum --quiet --yes install ansible
			;;

		Debian|Ubuntu|'Raspbian GNU/Linux')
			apt-get -qq update
			apt-get -qq install ansible
			;;
	esac
fi

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

log "Starting updater at $(date)"

DEVICE_ID=$(config .ansible.device_id)
API_HOST=$(config .ansible.api_host)

UPTIME=$(awk '{print $1}' /proc/uptime)

BODY="{\"action\" : \"job_stalling\", \"uptime\" : ${UPTIME}}"

RES=$(curl --header "Content-Type: application/json" \
    --write-out %{http_code} \
    --request POST \
    --data "$BODY" \
    $API_HOST/playbook.php?id=$DEVICE_ID \
    --output /tmp/playbook.zip
    )

echo $RES
if [ "$RES" == "204" ]; then
  echo "Nothing to do"
elif [ "$RES" == "200" ]; then
  echo "Execute Ansible"
  rm -rf /tmp/ansible
  mkdir /tmp/ansible
  cd /tmp/ansible
  unzip /tmp/playbook.zip -d /tmp/ansible

    ANSIBLE_FORCE_COLOR=1 \
    ansible-playbook playbook.yml -i inventory/hosts.yml --vault-password-file /boot/firmware/vaultkey.secret
fi

log "Finished update successfully at $(date)!"
