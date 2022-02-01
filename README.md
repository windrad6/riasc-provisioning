# RIasC Provisioning Scripts

[![GitHub](https://img.shields.io/github/license/ERIGrid2/riasc-provisioning)](https://github.com/ERIGrid2/riasc-provisioning/blob/master/LICENSE)

- **Based on:** <https://github.com/k3s-io/k3s-ansible>

## Introduction

This fork of the RIasC Provisioning scripts is modified for the use with the edgePMU

## Documentation

For further documentation, please consult: https://riasc.eu/docs/

## System requirements

The scripts have been tested with the following operating systems:

- Ubuntu 20.01

## Initial Setup
Before using this script, you will have to make sure that:
1. The referenced git repositories in `update_image.sh` exist and you have sufficient access rights.
2. Your ansible inventory is located at `{REPO}/inventory/edgeflex`
3. You have created the host_vars directory in your inventory
4. The password repository contains an initialized [*PASSWORD_STORE*](https://www.passwordstore.org/) with the subdirectories `keys` and `old`

## Usage

### 1. Creating an Image
See: https://riasc.eu/docs/setup/agent/manual

### 2. Updating an Image
Before flashing the created image, the `update_image.sh` script will write and update the necessary configuration files to the boot partition of the image.

Additionally, some of the configuration values are written into a git repository.

To run the `update_image.sh` script, execute the script as **root** an follow the usage guide.

i.e.
```
sudo ./update_image.sh -I PATH_TO_IMAGE_FROM_CREATE_IMAGE.SH -N edgepmuXX -B main -S ../../SSL/CERT -U your_git_username -P your_git_access_token
```

After the script has finished, the Image can be flashed to the Raspberry PI.

**Warning:** Running this script will override (and backup) old credentials, etc

### 3. Updating an edgePMU that is already flashed

To update an edgePMU that is already flashed, run the `update_image.sh` script with the *-u* option. This will lead to the configuration files getting written to the image and temporary files for you to manually copy to the device in question via SCP.

You will need to copy:
1. The generated `vaultkey.secret` to `/boot/firmware/vaultkey.secret`
2. The updated `riasc.yaml` to `/boot/firmware/riasc.yaml`
3. The updated `user-data` to `/boot/firmware/user-data`
4. The `git token` to `boot/firmware/git_token.secret`
5. The updated `../common/riasc-update.sh` to `/usr/local/bin/riasc-update.sh`

Other data such as new SNMP credentials or new vpn configuration files can be distributed via the pmu-ansible repo.

## Credits

- [Steffen Vogel](https://github.com/stv0g) [📧](mailto:post@steffenvogel.de), [Institute for Automation of Complex Power Systems](https://www.acs.eonerc.rwth-aachen.de), [RWTH Aachen University](https://www.rwth-aachen.de)

### Funding acknowledment

<img alt="European Flag" src="https://erigrid2.eu/wp-content/uploads/2020/03/europa_flag_low.jpg" align="left" style="margin-right: 10px"/> The development of [RIasC](https://riasc.eu) has been supported by the [ERIGrid 2.0](https://erigrid2.eu) project \
of the H2020 Programme under [Grant Agreement No. 870620](https://cordis.europa.eu/project/id/870620)
