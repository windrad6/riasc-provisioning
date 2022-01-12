#!/bin/bash
set -e

SCRIPT_PATH=$(dirname $(realpath "${BASH_SOURCE[0]}"))
pushd ${SCRIPT_PATH}

#======================= Predefined settings =====================
CONFIG_FILE="riasc.edgeflex.yaml"
SSL_SEARCH_PATH="./ssl"
ASK_CONFIRM=true

GIT_SERVER="git@git.rwth-aachen.de"
GIT_ANSIBLE_REPO=${GIT_SERVER}":acs/public/software/pmu/pmu-ansible.git"
GIT_PASS=${GIT_SERVER}":acs/public/software/pmu/pmu_pass.git"

#========================= Get User input =========================
usage(){
    echo "Usage:"
    echo "  -I  [Path to Image:                 -I /path/to/image/]"
    echo "  -N  [Hostname to use:               -N name]"
    echo "  -T  [Git !project! acces token:     -T GITLAB token]"
    echo "  -B  [Git branch                     -B development]"
    echo "  -S  [Path to SSL Cert:              -S /path/to/cert]"
    echo "  -y  [Dont ask for confirmations]"
    echo ""
    echo "Credentials for ansible/pass repo"
    echo "  -U  [${GIT_SERVER} username         -B myName]"
    echo "  -P  [${GIT_SERVER} pass/token       -P Token]"
    exit
}


while getopts ":I:N:T:B:S:yU:P:" opt
do
    case "${opt}" in
        I) IMAGE_FILE=${OPTARG};;
        S) SSL_CERT_FILE=${OPTARG} ;;
        N) NODENAME=${OPTARG} ;;
        y) ASK_CONFIRM=false ;;
        T) PMU_GIT_TOKEN=${OPTARG} ;;
        B) PMU_GIT_BRANCH=${OPTARG} ;;
        U) GIT_USERNAME=${OPTARG}
        P) GIT_PASS=${OPTARG}
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

#Ensure Nodename is supplied
if ! [[ -n ${NODENAME} ]]; then
    echo "No node name supplied"
    usage
fi

#Ensure git project token is supplied
if ! [[ -n ${PMU_GIT_TOKEN} ]]; then
    echo "No git acces token supplied"
    usage
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

exit
#========================= Check if we can access Git repos =========================
#Dont do for now

#Check if repos (pass + ansible) are available

#================================= Confirm settings =================================
echo "Gathered following configuration:"
echo "Nodename:     ${NODENAME}"
echo "Image:        ${IMAGE_FILE}"
echo "SSL_CERT:     ${SSL_CERT_FILE}"
echo "Config:       ${CONFIG_PATH}"

if [[ -n ${PMU_GIT_BRANCH} ]]; then
echo "Branch:       ${PMU_GIT_BRANCH}"
fi

if [[ ${ASK_CONFIRM} == true ]]; then
    echo "Continue? (Y,n)"
    read inp
    if ! [[ ${inp} == "Y" || ${inp} == "" ]]; then
        exit
    fi    
fi


#============================== Setup to create patch ==============================

#1. Create temp directory
echo "Creating temporary work directory"
if [[ -d ${NODENAME} ]]; then
    echo "Allready exists. Deleting"
    rm ${NODENAME} -r
fi
mkdir ${NODENAME}

#2. Copy files to work directory
echo "Copying files"
NODE_IMAGE_FILE="${NODENAME}_IMAGE"
cp ${IMAGE_FILE} "${NODENAME}/${NODE_IMAGE_FILE}.img"
cp ${SSL_CERT_FILE} "${NODENAME}/acs-lab.conf"
cp ${CONFIG_PATH} "${NODENAME}/riasc.yaml"
cp "user-data" "${NODENAME}/user-data"
echo "Done"

#3. Make sure repos are here


#4. Enter working directory
pushd ${NODENAME}

#5. Generate secrets and write to files
echo "Generating secrets"

#Vault Key
VAULT_KEY=$(openssl rand -hex 128)
cat <<EOF > vaultkey.secret
#!/bin/bash
echo "${VAULT_KEY}"
EOF

#Git token
echo ${PMU_GIT_TOKEN} > "git_token.secret" #TODO: braucht man das??

#SNMP key
SNMP_KEY=$(openssl rand -hex 10)
echo ${SNMP_KEY} > "snmp.secret" #TODO: braucht man das??

echo "Done"

#============================ Edit Files for Boot partition ============================

#1. Edit configuration files
echo "Writing configuration"

sed -i \
	-e "s/edgepmu/${NODENAME}/g" \
	riasc.yaml

#Select branch
if [[ -n ${PMU_GIT_BRANCH} ]]; then
    sed -i \
    -e "/url: /a\\\\tbranch: ${PMU_GIT_BRANCH}" riasc.yaml
fi

#Git token
if [[ -n ${PMU_GIT_TOKEN} ]]; then
    sed -i -e "s/git.rwth-aachen/pmu-acs:${PMU_GIT_TOKEN}@git.rwth-aachen/g" riasc.yaml
fi

#Node Name
sed -i \
	-e "s/exampleHost/${NODENAME}/g" \
	user-data

echo "Done"

#============================== Edit Files in git repo =============================

#1. Encrypt with ansible
#OpenVPN.
#SNMP Key

#2. Write variables to ansible-repo

#3. Commit and push ansible-repo

#4. Encrypt password with PGP key

#5. Push to pass repo

#================================== Write to Image ==================================

#1. Write patch file
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

#2. Write patch to image
echo "Patching image with guestfish..."
guestfish < edgeflex.fish

#3. Zip image

#echo "Zipping image..."
#rm -f ${NODE_IMAGE_FILE}.zip
#zip ${NODE_IMAGE_FILE}.zip ${NODE_IMAGE_FILE}.img
#rm -f ${NODE_IMAGE_FILE}.img
#echo "Done"

#4. Final outputs
echo "Please write the new image to an SD card:"
lsblk |grep sd
echo "  dd bs=1M if=${NODE_IMAGE_FILE}.img of=/dev/sdX"
