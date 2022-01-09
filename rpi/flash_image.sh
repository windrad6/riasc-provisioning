#!/bin/bash
set -e

SCRIPT_PATH=$(dirname $(realpath "${BASH_SOURCE[0]}"))
pushd ${SCRIPT_PATH}

#Predefined settings
CONFIG_FILE="riasc.edgeflex.yaml"
SSL_SEARCH_PATH="./ssl"
ASK_CONFIRM=true

#Get User input
usage(){
    echo "Usage:"
    echo "  -I  [Path to Image:                 -I /path/to/image/]"
    echo "  -N  [Hostname to use:               -N name]"
    echo "  -T  [Git !project! acces token:     -T GITLAB token]"
    echo "  -B  [Git branch                     -B development]"
    echo "  -S  [Path to SSL Cert:              -S /path/to/cert]"
    echo "  -y  [Dont ask for confirmations]"
    exit
}


while getopts ":I:N:T:B:S::y" opt
do
    case "${opt}" in
        I) IMAGE_FILE=${OPTARG};;
        S) SSL_CERT_FILE=${OPTARG} ;;
        N) NODENAME=${OPTARG} ;;
        y) ASK_CONFIRM=false ;;
        T) GIT_TOKEN=${OPTARG} ;;
        B) GIT_BRANCH=${OPTARG} ;;
        *) echo "Unknown argument ${OPTARG}"
           usage ;;
        :) usage ;;
    esac
done

if [ $OPTIND -eq 1 ]; then 
    echo "Not enougth options" 
    usage;
fi

#Ensure RIASC Image file is found
if ! [[ -r ${IMAGE_FILE} ]]; then #TODO: Check if this is a .zip file
    echo "Image file '${IMAGE_FILE}' does not exist"
    usage
fi

#Ensure nodename is supplied
if ! [[ -n ${NODENAME} ]]; then
    echo "No node name supplied"
    usage
fi

#if ! [[ -n ${GIT_TOKEN} ]]; then
#    echo "No git acces token supplied"
#    usage
#fi


#Try to find ssl cert file automatically if not supplied
if ! [[ -n ${SSL_CERT_FILE} ]]; then
    if [[ -r "${SSL_SEARCH_PATH}/gate-TCP4-1184-${NODENAME}.pmu.acs-lab.eonerc.rwth-aachen.de-config.ovpn" ]]; then
        SSL_CERT_FILE="${SSL_SEARCH_PATH}/gate-TCP4-1184-${NODENAME}.pmu.acs-lab.eonerc.rwth-aachen.de-config.ovpn"
        echo "Automatically found SSL cert file: ${SSL_CERT_FILE}"
    else
        echo "No SSL cert file supplied. Could not find one either."
        usage
    fi
fi


#Ensure SSL cert file is found
if ! [[ -r ${SSL_CERT_FILE} ]]; then
    echo "SSL cert file '${SSL_CERT_FILE}' does not exist"
    usage
fi

#Ensure default config is found
if [[ -r "${SCRIPT_PATH}/../common/${CONFIG_FILE}" ]]; then
    CONFIG_PATH="${SCRIPT_PATH}/../common/${CONFIG_FILE}"
else
    echo "Could not find default config at:"
    echo "${SCRIPT_PATH}/../common/${CONFIG_FILE}"
    exit
fi

#Confirm settings

echo "Gathered following configuration:"
echo "Nodename:     ${NODENAME}"
echo "Image:        ${IMAGE_FILE}"
echo "SSL_CERT:     ${SSL_CERT_FILE}"
echo "Config:       ${CONFIG_PATH}"

if [[ -n ${GIT_BRANCH} ]]; then
echo "Branch:       ${GIT_BRANCH}"
fi

if [[ ${ASK_CONFIRM} == true ]]; then
    echo "Continue? (Y,n)"
    read inp
    if ! [[ ${inp} == "Y" || ${inp} == "" ]]; then
        exit
    fi    
fi


#Start patching:
echo "Creating temporary work directory"
if [[ -d ${NODENAME} ]]; then
    echo "Allready exists. Deleting"
    rm ${NODENAME} -r
fi
mkdir ${NODENAME}

#copy what we need
echo "Copying files"
NODE_IMAGE_FILE="${NODENAME}_IMAGE"
cp ${IMAGE_FILE} "${NODENAME}/${NODE_IMAGE_FILE}.img"
cp ${SSL_CERT_FILE} "${NODENAME}/acs-lab.conf"
cp ${CONFIG_PATH} "${NODENAME}/riasc.yaml"
cp "user-data" "${NODENAME}/user-data"
echo "Done"

pushd ${NODENAME}

echo "Generating secrets"
#Ansible vault key (Currently not used but its there)
VAULT_KEY=$(openssl rand -hex 128)
cat <<EOF > vaultkey.secret
#!/bin/bash
echo "${VAULT_KEY}"
EOF


#GPG key pair
#TODO

echo ${GIT_TOKEN} > "git_token.secret"

echo "Done"

echo "Writing configuration"

sed -i \
	-e "s/edgepmu/${NODENAME}/g" \
	riasc.yaml

#Select branch
if [[ -n ${GIT_BRANCH} ]]; then
    sed -i \
    -e "/url: /a\\\\tbranch: ${GIT_BRANCH}" riasc.yaml
fi

#Git token
if [[ -n ${GIT_TOKEN} ]]; then
    sed -i -e "s/git.rwth-aachen/pmu-acs:${GIT_TOKEN}@git.rwth-aachen/g" riasc.yaml
fi

sed -i \
	-e "s/exampleHost/${NODENAME}/g" \
	user-data

echo "Done"

#Unzip the image file
#echo "Unzipping the image"
#unzip -p ${NODE_IMAGE_FILE}.zip > ${NODE_IMAGE_FILE}.img
#echo "Done"

echo "Writing Patch file"
cat <<EOF > edgeflex.fish
echo "Loading image..."
add ${NODE_IMAGE_FILE}.img

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
copy-in riasc.yaml /boot
copy-in user-data /boot
copy-in vaultkey.secret /boot
copy-in git_token.secret /boot

mkdir /boot/openvpn/
copy-in acs-lab.conf /boot/openvpn
EOF

#Write patch to image
echo "Patching image with guestfish..."
guestfish < edgeflex.fish

# Zip image
#echo "Zipping image..."
#rm -f ${NODE_IMAGE_FILE}.zip
#zip ${NODE_IMAGE_FILE}.zip ${NODE_IMAGE_FILE}.img
#rm -f ${NODE_IMAGE_FILE}.img
#echo "Done"

echo "Please write the new image to an SD card:"
lsblk |grep sd
echo "  dd bs=1M if=${NODE_IMAGE_FILE}.img of=/dev/sdX"
