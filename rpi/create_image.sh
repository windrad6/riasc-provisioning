#!/bin/bash

set -e

SCRIPT_PATH=$(dirname $(realpath "${BASH_SOURCE[0]}"))
cd "${SCRIPT_PATH}"

# Settings
NODENAME="${NODENAME:-riasc-agent}"
USERNAME="${USERNAME:-ubuntu}"
PASSWORD="${PASSWORD:-ubuntu}"
FORCE_PW_CHANGE=${FORCE_PW_CHANGE:-true}

DOWNLOAD_FOLDER="/tmp/data/download/"
OUTPUT_FOLDER="/tmp/data/output/"
IMG_FOLDER="/tmp/data/images/"
WORKDIR="/tmp/"
REPOFOLDER="/tmp/riasc/"
FLAVOR=${FLAVOR:-raspios}

if [ ! -d "$DOWNLOAD_FOLDER" ]; then
	mkdir ${DOWNLOAD_FOLDER}
fi
if [ ! -d "$OUTPUT_FOLDER" ]; then
	mkdir ${OUTPUT_FOLDER}
fi
if [ ! -d "$IMG_FOLDER" ]; then
	mkdir ${IMG_FOLDER}
fi

case ${FLAVOR} in
	ubuntu24.04)
		OS="ubuntu"
		;;
	ubuntu22.04)
		OS="ubuntu"
		;;
	ubuntu20.04)
		OS="ubuntu"
		;;
	raspios)
		OS="raspios"
		;;
	*)
		echo "Flavor $FLAVOR not known!"
		exit 0
		;;
esac

case ${FLAVOR} in
	ubuntu20.04)
		IMAGE_FILE="ubuntu-20.04.2-preinstalled-server-arm64+raspi"
		IMAGE_SUFFIX="img.xz"
		IMAGE_URL="https://cdimage.ubuntu.com/releases/20.04.2/release/${IMAGE_FILE}.${IMAGE_SUFFIX}"
		;;

	ubuntu22.04)
		IMAGE_FILE="ubuntu-22.04.4-preinstalled-server-arm64+raspi"
		IMAGE_SUFFIX="img.xz"
		IMAGE_URL="https://cdimage.ubuntu.com/releases/22.04/release/${IMAGE_FILE}.${IMAGE_SUFFIX}"
		;;

	ubuntu24.04)
		IMAGE_FILE="ubuntu-24.04.2-preinstalled-server-arm64+raspi"
		IMAGE_SUFFIX="img.xz"
		IMAGE_URL="https://cdimage.ubuntu.com/releases/24.04/release/${IMAGE_FILE}.${IMAGE_SUFFIX}"
		;;

	raspios)
		IMAGE_FILE="2021-05-07-raspios-buster-armhf-lite"
		IMAGE_SUFFIX="zip"
		IMAGE_URL="https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2021-05-28/${IMAGE_FILE}.${IMAGE_SUFFIX}"
		;;
esac

RIASC_IMAGE_FILE="$(date +%Y-%m-%d)-riasc-${NODENAME}"
if [ ! -z "$TAG" ]; then
	RIASC_IMAGE_FILE+="-${TAG}"
fi

function check_command() {
	if ! command -v "$1" &> /dev/null; then
		echo "$1 could not be found"
		exit
	fi
}

# Show config
echo "Using hostname: ${NODENAME}"
echo "Using flavor: ${FLAVOR}"
echo "Using device id: ${API_HOST}"
echo "Using API URL: ${DEVICE_ID}"
echo "Using User: ${USERNAME}"
echo "Using Password: ${PASSWORD}"
echo "Using Enfoce password change: ${FORCE_PW_CHANGE}"
if [ ! -z "$VAULT_KEY" ]; then
	echo "Using ansible secret: ${VAULT_KEY}"
fi
echo "Using Filename: ${RIASC_IMAGE_FILE}"




# Check that required commands exist
echo "Check if required commands are installed..."
check_command guestfish
check_command wget
check_command unzip
check_command zip
check_command xz
# dnf install guestfs-tools wget zip xz
# apt-get install libguestfs-tools wget unzip zip xz-utils

# Download image
cd ${DOWNLOAD_FOLDER}
if [ ! -f "${IMAGE_FILE}"."${IMAGE_SUFFIX}" ]; then
	echo "Downloading image..."
	wget \
  		--progress=bar:force \
		"${IMAGE_URL}"
else
	echo "${IMAGE_FILE}.${IMAGE_SUFFIX} exists skipping download"
fi


# Unzip image
cd ${IMG_FOLDER}

if [ ! -f "${IMAGE_FILE}".img ]; then
	echo "Unzipping image..."
	case ${IMAGE_SUFFIX} in
		img.xz)
			unxz --keep --threads=0 ${DOWNLOAD_FOLDER}/"${IMAGE_FILE}"."${IMAGE_SUFFIX}"
			mv ${DOWNLOAD_FOLDER}/"${IMAGE_FILE}".img ./
			;;
		zip)
			unzip "${DOWNLOAD_FOLDER}"/"${IMAGE_FILE}"."${IMAGE_SUFFIX}"
			;;
	esac
else
	echo "${IMAGE_FILE}.img exists skipping unpack"
fi

echo "Copying image..."
cd ${WORKDIR}

cp ${IMG_FOLDER}/"${IMAGE_FILE}".img "${RIASC_IMAGE_FILE}".img

# Prepare config


CONFIG_FILE="riasc.${OS}.yaml"

cp "${REPOFOLDER}"/common/${CONFIG_FILE} riasc.yaml

# Patch config
sed -i \
	-e "s,dummyAPIUrl,${API_HOST},g" \
	-e "s,dnummyId,${DEVICE_ID},g" \
	-e "s/dummyHostname/${NODENAME}/g" \
	riasc.yaml

if [ "${OS}" = "ubuntu" ]; then
	cp "${REPOFOLDER}"/rpi/user-data ${WORKDIR}/
	sed -i \
		-e "s/dummyHostname/${NODENAME}/g" \
		-e "s/replUSERNAME/${USERNAME}/g" \
		-e "s/replPASSWORD/${PASSWORD}/g" \
		-e "s/replExpire/${FORCE_PW_CHANGE}/g" \
		user-data
fi

#Generate ansible secret
if [ ! -f ${OUTPUT_FOLDER}/"${NODENAME}"-vaultkey.secret ]; then
	if [ -z "$VAULT_KEY" ]; then
		echo "Generate ansible secret"
		VAULT_KEY=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20; echo)
	fi
cat <<EOF > ${OUTPUT_FOLDER}/"${NODENAME}"-vaultkey.secret
#!/bin/bash
echo "${VAULT_KEY}"
EOF
	chmod +x ${OUTPUT_FOLDER}/"${NODENAME}"-vaultkey.secret
else
	echo "Skip ansible secret generation use existing key"
fi
cp ${OUTPUT_FOLDER}/"${NODENAME}"-vaultkey.secret ${WORKDIR}/vaultkey.secret


# Prepare systemd-timesyncd config
cat > fallback-ntp.conf <<EOF
[Time]
FallbackNTP=pool.ntp.org
EOF

# Download PGP keys for verifying Ansible Git commits
echo "Download PGP keys..."
mkdir -p keys
#wget -O keys/xxx.asc https://xxx
echo "repofolder ${REPOFOLDER}"
# Patching image
cat <<EOF > patch.fish
echo "Loading image..."
add ${RIASC_IMAGE_FILE}.img

echo "Start virtual environment..."
run

echo "Available filesystems:"
list-filesystems

echo "Mounting filesystems..."
mount /dev/sda2 /
mount /dev/sda1 /boot

echo "Available space:"
df-h

echo "Copy files into image..."
copy-in ${REPOFOLDER}/rpi/rootfs/etc/ /
copy-in ${WORKDIR}/riasc.yaml /boot
copy-in ${WORKDIR}/vaultkey.secret /boot

mkdir-p /etc/systemd/timesyncd.conf.d/
copy-in ${WORKDIR}/fallback-ntp.conf /etc/systemd/timesyncd.conf.d/

mkdir-p /usr/local/bin
copy-in ${REPOFOLDER}/common/http_update.sh ${REPOFOLDER}/common/riasc-set-hostname.sh ${REPOFOLDER}/common/heartbeat.sh /usr/local/bin/
glob chmod 755 /usr/local/bin/http_update.sh
glob chmod 755 /usr/local/bin/heartbeat.sh
glob chmod 755 /usr/local/bin/riasc-*.sh

copy-in ${WORKDIR}/keys/ /boot/

echo "Disable daily APT timers"
rm /etc/systemd/system/timers.target.wants/apt-daily-upgrade.timer
rm /etc/systemd/system/timers.target.wants/apt-daily.timer

echo "Updating os-release"
write-append /etc/os-release "VARIANT=\"RIasC\"\n"
write-append /etc/os-release "BUILD_ID=\"$(date)\"\n"
write-append /etc/os-release "DOCUMENTATION_URL=\"https://riasc.eu\"\n"
EOF

case ${OS} in
	ubuntu)
cat <<EOF >> patch.fish
copy-in ${WORKDIR}/user-data /boot
EOF
		;;
	*)
cat <<EOF >> patch.fish
echo "Enable SSH on boot..."
touch /boot/ssh

echo "Setting hostname..."
write /etc/hostname "${NODENAME}"

echo "Enable systemd risac services..."
ln-sf /etc/systemd/system/http-update.service /etc/systemd/system/multi-user.target.wants/http-update.service
ln-sf /etc/systemd/system/http-update.timer /etc/systemd/system/multi-user.target.wants/http-update.timer
ln-sf /etc/systemd/system/heartbeat.service /etc/systemd/system/multi-user.target.wants/heartbeat.service
ln-sf /etc/systemd/system/heartbeat.timer /etc/systemd/system/multi-user.target.wants/heartbeat.timer
ln-sf /etc/systemd/system/risac-set-hostname.service /etc/systemd/system/multi-user.target.wants/riasc-set-hostname.service
EOF
		;;
esac

if [ "${OS}" = "ubuntu" ]; then
cat <<EOF >> patch.fish
echo "Disable Grub boot"
write-append /boot/usercfg.txt "[all]\ninitramfs initrd.img followkernel\nkernel=vmlinuz\n"
EOF
fi

echo "Patching image with guestfish..."
guestfish < patch.fish

if [ "${RAW_OUTPOUT}" = "yes" ]; then
	echo "Copy raw image..."
	cp "${RIASC_IMAGE_FILE}".img ${OUTPUT_FOLDER}/
fi

# Zip image
echo "Zipping image..."
rm -f "${RIASC_IMAGE_FILE}".zip
zip ${OUTPUT_FOLDER}/"${RIASC_IMAGE_FILE}".zip "${RIASC_IMAGE_FILE}".img
chmod o+w ${OUTPUT_FOLDER}/"${RIASC_IMAGE_FILE}".zip

echo "Please write the new image to an SD card:"
echo "  dd bs=1M if=${RIASC_IMAGE_FILE}.img of=/dev/sdX"