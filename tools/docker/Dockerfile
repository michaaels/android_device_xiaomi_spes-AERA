# Reproducible build environment for AERA Recovery (aera-16.0 / Android 16).
# AOSP ships its own clang, JDK and Python-adjacent prebuilts; the host image
# only needs the classic AOSP host packages plus `repo`.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG USER_UID=1000
ARG USER_GID=1000
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8 TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
        bc bison build-essential ca-certificates ccache curl e2fsprogs file \
        flex fontconfig g++-multilib gcc-multilib git git-lfs gnupg gperf \
        lib32z1-dev libc6-dev-i386 libelf-dev libgl1-mesa-dev libssl-dev \
        libxml2-utils lz4 make openssl python3 python-is-python3 rsync \
        schedtool sudo unzip util-linux x11proto-core-dev xsltproc zip \
        zlib1g-dev cpio kmod xxd \
    && rm -rf /var/lib/apt/lists/*

# repo launcher from the official Google bucket
RUN curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo \
    && chmod 0755 /usr/local/bin/repo

# Unprivileged build user matching the host uid/gid (ubuntu:24.04 ships uid 1000 "ubuntu")
RUN (userdel -r ubuntu 2>/dev/null || true) \
    && groupadd -g ${USER_GID} builder \
    && useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash builder \
    && git config --system user.name "AERA spes builder" \
    && git config --system user.email "builder@localhost" \
    && git config --system color.ui false

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
