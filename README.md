# Raspberry PI Image generation

This project generates and customizes a Raspberry Pi image, either for Ubuntu or Raspberry Pi OS. The script is build for running within a docker container.

The customizations include:
* Generating or adding a `vaultkey.secret` file
* Updating Ansible configuration in `/boot/firmware/riasc.yaml`
* Updating cloud-init file in `/boot/firmware/user-data`
* Setting GIT Ansible repor in `/boot/firmware/riasc.yaml`
* Adding and enabling GIT based Ansible updates on reboot


## Usage

1) Switch to direcory with Dockerfile to build image
```
docker build --tag "imagebuilder" .
```
2) Create `env` file:
```
GIT_URL=https://mygiturl
FLAVOR=ubuntu22.04
GIT_BRANCH=mybranch
GIT_TOKEN=mytoken
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
5) Copy image to SD card. Either using dd or the Raspberry Pi Imiger


## List of available variables
| Variable | Info |
| - | - |
|GIT_URL | URL to ansible git repository|
|FLAVOR | Falvor of os. See list of flavors|
|GIT_BRANCH | Branch used in ansible git pull|
|GIT_TOKEN | Token unsed in ansible git pull|
|NODENAME | The hostname of the device|
|TAG | A tag that is added to the name|
|RAW_OUTPOUT | Set to yes to get the .img file as output|
|TOKEN | A token used by Ansible|

### List of flavors

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
Copy the file in `out/output`. and make sure that the name is NODENAME-vaultkey.secret


[![GitHub](https://img.shields.io/github/license/ERIGrid2/riasc-provisioning)](https://github.com/ERIGrid2/riasc-provisioning/blob/master/LICENSE)


## Credits

- [Steffen Vogel](https://github.com/stv0g) [📧](mailto:post@steffenvogel.de), [Institute for Automation of Complex Power Systems](https://www.acs.eonerc.rwth-aachen.de), [RWTH Aachen University](https://www.rwth-aachen.de)
- [Vincent Bareiß]() [📧](mailto:), [Institute for Automation of Complex Power Systems](https://www.acs.eonerc.rwth-aachen.de), [RWTH Aachen University](https://www.rwth-aachen.de)
- [Manuel Pitz](https://https://github.com/windrad6) [📧](mailto:post@cl0.de), [Institute for Automation of Complex Power Systems](https://www.acs.eonerc.rwth-aachen.de), [RWTH Aachen University](https://www.rwth-aachen.de)

### Funding acknowledment

<img alt="European Flag" src="https://erigrid2.eu/wp-content/uploads/2020/03/europa_flag_low.jpg" align="left" style="margin-right: 10px"/> The development of [RIasC](https://riasc.eu) has been supported by the [ERIGrid 2.0](https://erigrid2.eu) project \
of the H2020 Programme under [Grant Agreement No. 870620](https://cordis.europa.eu/project/id/870620)
