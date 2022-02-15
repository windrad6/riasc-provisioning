from ubuntu:latest

#Get dependencies
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get -y install tzdata
RUN apt-get install -y jq ansible pass curl gpg git wget unzip zip
ENV LIBGUESTFS_BACKEND=direct

WORKDIR edgepmu
RUN apt-get update && apt-get install --no-install-recommends -y libguestfs-tools qemu-utils linux-image-generic
RUN git clone https://github.com/cl0-de/riasc-provisioning.git -b development
ENV FLAVOR=edgeflex
ENV LIBGUESTFS_DEBUG=1 
ENV LIBGUESTFS_TRACE=1
RUN ./riasc-provisioning/rpi/create_image.sh

CMD /bin/bash