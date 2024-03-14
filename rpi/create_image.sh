#!/bin/bash

set -e

SCRIPT_PATH=$(dirname $(realpath "${BASH_SOURCE[0]}"))
cd "${SCRIPT_PATH}"

# Settings
NODENAME="${NODENAME:-riasc-agent}"
TOKEN="${TOKEN:-XXXXX}"

DOWNLOAD_FOLDER="/tmp/download/"
OUTPUT_FOLDER="/tmp/output/"
IMG_FOLDER="/tmp/images/"
WORKDIR="/tmp/"
REPOFOLDER="/tmp/blubber/"

FLAVOR=${FLAVOR:-raspios}

case ${FLAVOR} in
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

	raspios)
		IMAGE_FILE="2021-05-07-raspios-buster-armhf-lite"
		IMAGE_SUFFIX="zip"
		IMAGE_URL="https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2021-05-28/${IMAGE_FILE}.${IMAGE_SUFFIX}"
		;;
esac

RIASC_IMAGE_FILE="$(date +%Y-%m-%d)-riasc-${OS}"

function check_command() {
	if ! command -v "$1" &> /dev/null; then
		echo "$1 could not be found"
		exit
	fi
}

# Show config
echo "Using hostname: ${NODENAME}"
echo "Using token: ${TOKEN}"

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
	wget "${IMAGE_URL}"
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

cp ${REPOFOLDER}/common/${CONFIG_FILE} riasc.yaml

# Patch config
sed -i \
	-e "s/XXXXX/${TOKEN}/g" \
	-e "s/riasc-agent/${NODENAME}/g" \
	riasc.yaml

# Prepare systemd-timesyncd config
cat > fallback-ntp.conf <<EOF
[Time]
FallbackNTP=pool.ntp.org
EOF

# Download PGP keys for verifying Ansible Git commits
echo "Download PGP keys..."
mkdir -p keys
#wget -O keys/xxx.asc https://xxx

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

mkdir-p /etc/systemd/timesyncd.conf.d/
copy-in ${REPOFOLDER}/rpi/fallback-ntp.conf /etc/systemd/timesyncd.conf.d/

mkdir-p /usr/local/bin
copy-in ${REPOFOLDER}/common/riasc-update.sh ${REPOFOLDER}/common/riasc-set-hostname.sh /usr/local/bin/
glob chmod 755 /usr/local/bin/riasc-*.sh

copy-in ${REPOFOLDER}/rpi/keys/ /boot/

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
copy-in ${REPOFOLDER}/rpi/user-data /boot
EOF
		;;
	*)
cat <<EOF >> patch.fish
echo "Enable SSH on boot..."
touch /boot/ssh

echo "Setting hostname..."
write /etc/hostname "${NODENAME}"

echo "Enable systemd risac services..."
ln-sf /etc/systemd/system/risac-update.service /etc/systemd/system/multi-user.target.wants/riasc-update.service
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


# Zip image
echo "Zipping image..."
rm -f "${RIASC_IMAGE_FILE}".zip
zip ${OUTPUT_FOLDER}/"${RIASC_IMAGE_FILE}".zip "${RIASC_IMAGE_FILE}".img

echo "Please write the new image to an SD card:"
echo "  dd bs=1M if=${RIASC_IMAGE_FILE}.img of=/dev/sdX"