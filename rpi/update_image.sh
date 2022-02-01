#!/bin/bash
set -e

SCRIPT_PATH=$(dirname $(realpath "${BASH_SOURCE[0]}"))
SCRIPT_OWNER=$(stat -c '%U' ${SCRIPT_PATH})
pushd ${SCRIPT_PATH}

#====================== Required Packages ========================
#jq, ansible-vault (ansible), pass


#======================= Predefined settings =====================
CONFIG_FILE="riasc.edgeflex.yaml"
SSL_SEARCH_PATH="./ssl"
ASK_CONFIRM=true
UPDATE=false
DEBUG=false

GIT_SERVER="git.rwth-aachen.de"
GIT_USE_KEY=false
GIT_MIN_ACCESS_LEVEL=40

GIT_ANSIBLE_REPO_NAME="pmu-ansible"
GIT_ANSIBLE_REPO_ID=61980
GIT_ANSIBLE_REPO="${GIT_SERVER}/acs/public/software/pmu/${GIT_ANSIBLE_REPO_NAME}.git"

GIT_PASS_REPO_NAME="PMU_pass"
GIT_PASS_REPO_ID=67640
GIT_PASS_REPO="${GIT_SERVER}/acs/public/software/pmu/${GIT_PASS_REPO_NAME}.git"

PASS_GPG_DIR="gpg"
PASS_GPG_KEYRING="${PASS_GPG_DIR}/keyring.gpg"
PASS_GPG_OPTIONS="--no-default-keyring --keyring ${PASS_GPG_KEYRING} --homedir ${PASS_GPG_DIR}"

#======================= Convenience Functions ====================
function pass_cmd() {
    PASSWORD_STORE_DIR="${SCRIPT_PATH}/${NODENAME}/${GIT_PASS_REPO_NAME}" PASSWORD_STORE_GPG_OPTS=${PASS_GPG_OPTIONS} PASSWORD_STORE_CLIP_TIME=1 pass $@ 
}

#========================= Get User input =========================
usage(){
    echo "Usage:"
    echo "  -I  [Path to Image:                 -I /path/to/image/]"
    echo "  -N  [Hostname to use:               -N name]"
    echo "  -B  [Git branch for ansible repo    -B development]"
    echo "  -S  [Path to SSL Cert:              -S /path/to/cert]"
    echo "  -y  [Dont ask for confirmations]"
    echo "  -d  [Debug mode. Dont delete temp files. Dont push to Repos]"
    echo "  -u  [Update mode. Dont delete temp files but push to Repos]"
    echo ""
    echo "Credentials for ansible/pass repo"
    echo "  -U  [${GIT_SERVER} username         -U myName]" #Needed?
    echo "  -P  [${GIT_SERVER} pass/token       -P Token]"
    exit
}


while getopts ":I:N:B:S:U::P::ydu" opt
do
    case "${opt}" in
        I) IMAGE_FILE=${OPTARG};;
        S) SSL_CERT_FILE=${OPTARG} ;;
        N) NODENAME=${OPTARG} ;;
        y) ASK_CONFIRM=false ;;
        d) DEBUG=true ;;
	u) UPDATE=true ;;
	B) PMU_GIT_BRANCH=${OPTARG} ;;
        U) GIT_USERNAME=${OPTARG} ;;
        P) GIT_PASS=${OPTARG} ;;
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
if ! [[ -r ${IMAGE_FILE} ]]; then
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

if [[ ${DEBUG} = true ]]; then
    echo "Running in Debug mode"
fi

if [[ ${UPDATE} = true ]]; then
    echo "Running in Update mode"
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
echo "Cloning GIT repos"
git clone "https://${GIT_USERNAME}:${GIT_PASS}@${GIT_PASS_REPO}"
git clone "https://${GIT_USERNAME}:${GIT_PASS}@${GIT_ANSIBLE_REPO}" -b ${PMU_GIT_BRANCH:main}
pass_cmd git init #tell pass we want to create commits when working with passwords
echo "Done"

#5. Import GPG keys 
echo "Setting up GPG keyring / trustdb"
mkdir ${PASS_GPG_DIR}
touch ${PASS_GPG_KEYRING}
chmod 600 ${PASS_GPG_DIR}/*
chmod 700 ${PASS_GPG_DIR}

gpg ${PASS_GPG_OPTIONS} --import $(ls -1 ${GIT_PASS_REPO_NAME}/keys/*.acs)
for keyfile in $(ls -1 ${GIT_PASS_REPO_NAME}/keys/*.acs| xargs basename -a -s .acs); do
    echo "${keyfile}:6:" | gpg ${PASS_GPG_OPTIONS} --import-ownertrust;
done
echo "Done"

#6. Generate secrets and write to files
echo "Generating secrets"

#Vault Key
#backup existing password if exists
if [[ -r ${GIT_PASS_REPO_NAME}/${NODENAME}.gpg ]]; then
    echo "Backing old PW up"
    pass_cmd mv ${NODENAME} "old/${NODENAME}_$(date '+%Y-%m-%d_%H:%M:%S')" 
fi

VAULT_KEY=$(pass_cmd generate ${NODENAME} -n 20 | tail -1) #TODO: this is not a pretty way to do this...

cat <<EOF > vaultkey.secret
#!/bin/bash
echo "${VAULT_KEY}"
EOF
chmod +x vaultkey.secret

#Git token
#request git token from API
if [[ ${DEBUG} = false ]]; then
    TOKEN_RESP_J=$(curl -s --request POST --header "PRIVATE-TOKEN: ${GIT_PASS}" --header "Content-Type:application/json" --data "{ \"name\":\"${NODENAME}\", \"scopes\":[\"read_repository\"]}" "${GIT_API_URL}/projects/${GIT_ANSIBLE_REPO_ID}/access_tokens")
    PMU_GIT_TOKEN=$(echo ${TOKEN_RESP_J} | jq -r '.token')
else
    PMU_GIT_TOKEN="TEMPTOKEN"
    echo "DID NOT GENERATE TOKEN DUE TO DEBUG MODE"
fi
echo ${PMU_GIT_TOKEN}
if [ -z ${PMU_GIT_TOKEN} ]; then
    echo "Error while creating git access token"
    exit
fi

echo ${PMU_GIT_TOKEN} > "git_token.secret"

#SNMP pass
SNMP_PASS=$(openssl rand -hex 10)

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
    -e "/url: /a\\  branch: ${PMU_GIT_BRANCH}" riasc.yaml
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
ansible-vault encrypt --vault-password-file ./vaultkey.secret acs-lab.conf --output acs-lab.conf.secret
#SNMP
SNMP_PASS_VAULT=$(ansible-vault encrypt_string --vault-password-file ./vaultkey.secret --name SNMP_PASS ${SNMP_PASS})

#2. Write variables to ansible-repo
#make sure host bin exists
HOST_BIN="./${GIT_ANSIBLE_REPO_NAME}/inventory/edgeflex/host_vars/${NODENAME}"
if ! [[ -d ${HOST_BIN} ]]; then
    mkdir ${HOST_BIN}
fi

#Replace SNMP Pass
cat <<EOF > ./${GIT_ANSIBLE_REPO_NAME}/inventory/edgeflex/host_vars/${NODENAME}/snmp.yml
${SNMP_PASS_VAULT}
SNMP_USR: ${NODENAME}
EOF

#Replace openVPN config
cp ./acs-lab.conf.secret ${HOST_BIN}

#3. Commit and push ansible-repo
pushd ${GIT_ANSIBLE_REPO_NAME}
git add .
git commit -m "Running update_image on $(date) for ${NODENAME}" --author="Update Image Script<vincent.bareiss@rwth-aachen.de>"
if ! [ ${DEBUG} = true ]; then
    git push
else
    echo "Didnt push to ansible repo due to debug mode"
fi
popd

#5. Push to pass repo
pushd ${GIT_PASS_REPO_NAME}
if ! [ ${DEBUG} = true ]; then
    pass_cmd git push
else
    echo "Didnt push to pass repo due to debug mode"
fi
popd

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


#4. Clean up
if [[ ${DEBUG} == false ]] && [[ ${UPDATE} == false ]]; then
    echo "removing files"
    rm "acs-lab.conf"
    rm "edgeflex.fish"
    rm "riasc.yaml"
    rm "user-data"
    rm *.secret
    rm ${PASS_GPG_DIR} -r
    rm ${GIT_PASS_REPO_NAME} -r
    rm ${GIT_ANSIBLE_REPO_NAME} -r
fi


#4. Final outputs
echo "Please write the new image to an SD card:"
lsblk |grep sd
echo "  dd bs=1M if=${NODE_IMAGE_FILE}.img of=/dev/sdX"
