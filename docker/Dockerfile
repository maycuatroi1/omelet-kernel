# Yocto (scarthgap) build host for the Omelet Pi 4 image.
# Based on Debian 12 (bookworm) which Yocto scarthgap supports.
# Built locally from an already-cached base so it needs no registry pull.
FROM node:20-slim

ENV DEBIAN_FRONTEND=noninteractive

# Yocto host dependencies + kas + logo-conversion tooling (imagemagick/netpbm).
RUN apt-get update && apt-get install -y --no-install-recommends \
        gawk wget git diffstat unzip texinfo gcc g++ build-essential chrpath \
        socat cpio python3 python3-pip python3-pexpect python3-git python3-jinja2 \
        python3-subunit xz-utils debianutils iputils-ping zstd liblz4-tool file \
        locales libacl1 bzip2 lz4 tar rsync curl bc ca-certificates \
        gosu sudo procps \
        imagemagick netpbm \
    && rm -rf /var/lib/apt/lists/*

# Yocto needs a UTF-8 locale.
RUN sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# kas pinned to match the project.
RUN pip3 install --no-cache-dir --break-system-packages kas==4.6

# bitbake refuses to run as root -> dedicated builder user.
RUN useradd -ms /bin/bash builder

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
