#!/bin/bash
set -e
set -x

SCRIPT_PATH=$(dirname $(realpath "${BASH_SOURCE[0]}"))
SCRIPT_OWNER=$(stat -c '%U' ${SCRIPT_PATH})
pushd ${SCRIPT_PATH}


#======================= Predefined settings =====================
CONFIG_FILE="riasc.edgeflex.yaml"
SSL_SEARCH_PATH="./ssl"
ASK_CONFIRM=true
DEBUG=false

GIT_SERVER="git.rwth-aachen.de"
GIT_USE_KEY=false
GIT_MIN_ACCESS_LEVEL=40

GIT_ANSIBLE_REPO_NAME="pmu-ansible"
GIT_ANSIBLE_REPO_ID=67607
GIT_ANSIBLE_REPO="${GIT_SERVER}/acs/public/software/pmu/${GIT_ANSIBLE_REPO_NAME}.git"

GIT_PASS_REPO_NAME="PMU_pass"
GIT_PASS_REPO_ID=67640
GIT_PASS_REPO="${GIT_SERVER}/acs/public/software/pmu/${GIT_PASS_REPO_NAME}.git"

#========================= Get User input =========================
usage(){
    echo "Usage:"
    echo "  -I  [Path to Image:                 -I /path/to/image/]"
    echo "  -N  [Hostname to use:               -N name]"
    echo "  -B  [Git branch                     -B development]"
    echo "  -S  [Path to SSL Cert:             -S /path/to/cert]"
    echo "  -y  [Dont ask for confirmations]"
    echo ""
    echo "Credentials for ansible/pass repo"
    echo "  -U  [${GIT_SERVER} username         -U myName]"
    echo "  -P  [${GIT_SERVER} pass/token       -P Token]"
    exit
}


while getopts ":I:N:B:S:U::P::yd" opt
do
    case "${opt}" in
        I) IMAGE_FILE=${OPTARG};;
        S) SSL_CERT_FILE=${OPTARG} ;;
        N) NODENAME=${OPTARG} ;;
        y) ASK_CONFIRM=false ;;
        B) PMU_GIT_BRANCH=${OPTARG} ;;
        U) GIT_USERNAME=${OPTARG} ;;
        P) GIT_PASS=${OPTARG} ;;
        d) DEBUG=true ;;
        *) echo "Unknown argument ${OPTARG}"
           usage ;;
        :) usage ;;
    esac
done


#if [ $OPTIND -eq 1 ]; then 
#    echo "Not enougth options" 
#    usage;
#fi

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

#========================= Check if we can access Git repos =========================
GIT_API_URL="https://${GIT_SERVER}/api/v4"
GIT_API_AUTH_HEADER="--header 'PRIVATE-TOKEN: ${GIT_PASS}'"

#Check Permissions on ansible repo via gitlab api
GIT_ANSIBLE_PERM_J=$(curl -s --header "PRIVATE-TOKEN: ${GIT_PASS}" ${GIT_API_URL}/projects/${GIT_ANSIBLE_REPO_ID} | jq -r '.permissions')
if [[ $(echo ${GIT_ANSIBLE_PERM_J} | jq -r '.group_access.access_level') -lt ${GIT_MIN_ACCESS_LEVEL} ]] && [[ $(echo ${GIT_ANSIBLE_PERM_J} | jq -r '.project_access.access_level') -lt ${GIT_MIN_ACCESS_LEVEL} ]]; then
    echo "You appear to not have the right permissions for the ${GIT_ANSIBLE_REPO_NAME} repository"
    echo "Please make sure that you have an access of at least ${GIT_MIN_ACCESS_LEVEL}"
    exit
fi

#Check Permissions on pass repo via gitlab api
GIT_PASS_PERM_J=$(curl -s --header "PRIVATE-TOKEN: ${GIT_PASS}" ${GIT_API_URL}/projects/${GIT_PASS_REPO_ID} | jq -r '.permissions')
if [[ $(echo ${GIT_PASS_PERM_J} | jq -r '.group_access.access_level') -lt ${GIT_MIN_ACCESS_LEVEL} ]] && [[ $(echo ${GIT_PASS_PERM_J} | jq -r '.project_access.access_level') -lt ${GIT_MIN_ACCESS_LEVEL} ]]; then
    echo "You appear to not have the right permissions for the ${GIT_PASS_REPO_NAME} repository"
    echo "Please make sure that you have an access of at least ${GIT_MIN_ACCESS_LEVEL}"
    exit
fi

#================================= Confirm settings =================================
echo "Gathered following configuration:"
echo "Nodename:     ${NODENAME}"
echo "Image:        ${IMAGE_FILE}"
echo "SSL_CERT:     ${SSL_CERT_FILE}"
echo "Config:       ${CONFIG_PATH}"
echo "Git User:     ${GIT_USERNAME}"

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

#3. Enter working directory
pushd ${NODENAME}

#4. Make sure repos are here
git clone "https://${GIT_USERNAME}:${GIT_PASS}@${GIT_PASS_REPO}"
git clone "https://${GIT_USERNAME}:${GIT_PASS}@${GIT_ANSIBLE_REPO}" -b ${PMU_GIT_BRANCH:main}

#5. Generate secrets and write to files
echo "Generating secrets"

#Vault Key
VAULT_KEY=$(openssl rand -hex 128)
cat <<EOF > vaultkey.secret
#!/bin/bash
echo "${VAULT_KEY}"
EOF

#Git token
#request git token from API TODO: check if old token exists and delte
TOKEN_RESP_J=$(curl -s --request POST --header "PRIVATE-TOKEN: ${GIT_PASS}" --header "Content-Type:application/json" --data "{ \"name\":\"${NODENAME}\", \"scopes\":[\"read_repository\"]}" "${GIT_API_URL}/projects/${GIT_ANSIBLE_REPO_ID}/access_tokens")
PMU_GIT_TOKEN=$(echo ${TOKEN_RESP_J} | jq -r '.token')
echo ${PMU_GIT_TOKEN}
if [ -z ${PMU_GIT_TOKEN} ]; then
    echo "Error while creating git access token"
    exit
fi

echo ${PMU_GIT_TOKEN} > "git_token.secret" #TODO: braucht man das??

#SNMP pass
SNMP_PASS=$(openssl rand -hex 10)
echo ${SNMP_PASS} > "snmp.secret" #TODO: braucht man das??

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
sed -i -e "s/git.rwth-aachen/pmu-acs:${PMU_GIT_TOKEN}@git.rwth-aachen/g" riasc.yaml

#Node Name
sed -i \
	-e "s/exampleHost/${NODENAME}/g" \
	user-data

echo "Done"

#============================== Edit Files in git repo =============================

#1. Encrypt with ansible
#OpenVPN.
ansible-vault encrypt --vault-password-file ./vaultkey.secret acs-lab.conf

#SNMP
SNMP_PASS_VAULT=$(ansible-vault encrypt_string --vault-password-file ./vaultkey.secret --name SNMP_PASS ${SNMP_PASS})
echo ${SNMP_PASS_VAULT}
#2. Write variables to ansible-repo
#make sure host bin exists


#3. Commit and push ansible-repo

#4. Encrypt password with PGP key

#5. Push to pass repo

#================================== Write to Image ==================================
exit
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


#4. Clean up
if [[ DEBUG == false ]]; then
echo "removing stuff"
rm "acs-lab.conf"
rm "edgeflex.fish"
rm "riasc.yaml"
rm "user-data"
rm "*.secret"
fi


#4. Final outputs
echo "Please write the new image to an SD card:"
lsblk |grep sd
echo "  dd bs=1M if=${NODE_IMAGE_FILE}.img of=/dev/sdX"
