FROM ubuntu:22.04

#Get dependencies
RUN DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC  apt update && apt-get -y install tzdata
ENV LIBGUESTFS_BACKEND=direct

WORKDIR /tmp
RUN apt-get install --no-install-recommends --no-install-suggests -y libguestfs-tools qemu-utils linux-image-generic wget unzip zip
# RUN git clone https://github.com/cl0-de/riasc-provisioning.git -b development
ENV FLAVOR=raspios
ENV REPOFOLDER=/tmp
# ENV LIBGUESTFS_DEBUG=1 
# ENV LIBGUESTFS_TRACE=1
# RUN ./riasc-provisioning/rpi/create_image.sh

CMD ${REPOFOLDER}/rpi/create_image.sh