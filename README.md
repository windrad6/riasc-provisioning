# Raspberry PI Image Generation

This project generates and customizes a Raspberry Pi image, either for Ubuntu or Raspberry Pi OS. The script is built for running within a docker container.

The customizations include:
* Generating or adding a `vaultkey.secret` file
* Updating Ansible configuration in `/boot/firmware/riasc.yaml`
* Updating cloud-init file in `/boot/firmware/user-data`
* Setting GIT Ansible repor in `/boot/firmware/riasc.yaml`
* Adding and enabling GIT based Ansible updates on reboot


## Usage

1) Switch to directory with Dockerfile to build image
```
docker build --tag "imagebuilder" .
```
2) Create `env` file:
```
GIT_URL=https://mygiturl
FLAVOR=ubuntu22.04
GIT_BRANCH=mybranch
NODENAME=myhost
TAG=test
```
3) Run docker container to generate image
```
docker run \
--volume ./:/tmp/riasc \
--volume ./out/:/tmp/data \
--env-file ./env \
imagebuilder
```
4) Image is placed in ´out/output´ folder
5) Copy image to SD card. Either using dd or the Raspberry Pi Imager


## List of Available Variables
| Variable | Info | Default | OS
| - | - | - | - |
|FLAVOR | Flavor of os. See list of flavors| - | All |
|NODENAME | The hostname of the device| - | All |
|TAG | A tag that is added to the name| - | All |
|RAW_OUTPOUT | Set to yes to get the .img file as output| - | All |
|VAULT_KEY | Key to use in the vaultkey.secret file| - | All |
|API_HOST| Hostname of API server | - | All |
|DEVICE_ID | UUID of this device | - | All |
|USERNAME | Set user for device | ubuntu | Ubuntu |
|PASSWORD | Set the password for the device | ubuntu | Ubuntu |
|FORCE_PW_CHANGE | Force use to change password on first login | true | Ubuntu |

### List of Flavors

ubuntu24.04

ubuntu22.04

ubuntu20.04

raspios


# Help

## How to mount the generated image to check the content?

Check for the partitions in the image file:

`fdisk -lu ubuntu-22.04.4-preinstalled-server-arm64+raspi.img`

Run mount command. Make sure to update the offset (526336) for the correct value

`mount ubuntu-22.04.4-preinstalled-server-arm64+raspi.img -o loop,offset=$(( 512 * 526336)) /mnt/`

## How to add my custom secrets file for ansible vaults?

To use a custom secret the VAULT_KEY variable can be set. If a vaultkey file of the name NODENAME-vaultkey.secret already exists the variable will be ignored.

[![GitHub](https://img.shields.io/github/license/ERIGrid2/riasc-provisioning)](https://github.com/ERIGrid2/riasc-provisioning/blob/master/LICENSE)


## Credits

- [Steffen Vogel](https://github.com/stv0g) [📧](mailto:post@steffenvogel.de), [Institute for Automation of Complex Power Systems](https://www.acs.eonerc.rwth-aachen.de), [RWTH Aachen University](https://www.rwth-aachen.de)
- [Vincent Bareiß]() [📧](mailto:), [Institute for Automation of Complex Power Systems](https://www.acs.eonerc.rwth-aachen.de), [RWTH Aachen University](https://www.rwth-aachen.de)
- [Manuel Pitz](https://github.com/windrad6) [📧](mailto:post@cl0.de), [Institute for Automation of Complex Power Systems](https://www.acs.eonerc.rwth-aachen.de), [RWTH Aachen University](https://www.rwth-aachen.de)

### Funding acknowledgment

<img alt="European Flag" src="https://erigrid2.eu/wp-content/uploads/2020/03/europa_flag_low.jpg" align="left" style="margin-right: 10px"/> The development of [RIasC](https://riasc.eu) has been supported by the [ERIGrid 2.0](https://erigrid2.eu) project \
of the H2020 Programme under [Grant Agreement No. 870620](https://cordis.europa.eu/project/id/870620)
