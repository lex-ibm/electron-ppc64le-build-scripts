# FROM registry.access.redhat.com/ubi8/ubi:latest
FROM quay.io/almalinuxorg/almalinux:8.10

RUN dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm && \
    /usr/bin/crb enable && \
    # dnf config-manager --enable "codeready-builder-for-rhel-8-$(arch)-rpms" && \
    dnf module enable -y nodejs:20 && \
    dnf install -y  clang \
                    clang-tools-extra \
                    llvm \
                    lld \
                    rustc \
                    bindgen-cli \
                    alsa-lib-devel \
                    atk-devel \
                    bison \
                    cups-devel \
                    dbus-devel \
                    desktop-file-utils \
                    expat-devel \
                    flex \
                    fontconfig-devel \
                    glib2-devel \
                    glibc-devel \
                    gperf \
                    compiler-rt \
                    libatomic \
                    libcap-devel \
                    libcurl-devel \
                    libdrm-devel \
                    libgcrypt-devel \
                    libudev-devel \
                    libuuid-devel \
                    libusb-devel \
                    libutempter-devel \
                    libXdamage-devel \
                    libXtst-devel \
                    xcb-proto \
                    mesa-libgbm-devel \
                    nss-devel \
                    pciutils-devel \
                    pulseaudio-libs-devel \
                    libappstream-glib \
                    bzip2-devel \
                    dbus-glib-devel \
                    elfutils \
                    elfutils-libelf-devel \
                    /usr/bin/git \
                    hwdata \
                    kernel-headers \
                    libffi-devel \
                    libxshmfence-devel \
                    mesa-libGL-devel \
                    "pkgconfig(gtk+-3.0)" \
                    /usr/bin/python3.9 \
                    /usr/bin/pip-3.9 \
                    re2-devel \
                    speech-dispatcher-devel \
                    yasm \
                    zlib-devel \
                    pam-devel \
                    systemd \
                    ninja-build \
                    java-1.8.0-openjdk-headless \
                    libevdev-devel \
                    xz \
                    patch \
                    wget \
                    nano \
                    libpng-devel \
                    libnotify-devel \
                    gcc-toolset-13-libatomic-devel \
                    nodejs \
                    yarnpkg \
                    ; \
    pip-3.9 install httplib2 && \
    alternatives --set python /usr/bin/python3.9 && \
    alternatives --set python3 /usr/bin/python3.9

RUN --mount=type=bind,source=patches/fix-depot-tools.patch,dst=/tmp/fix-depot-tools.patch \
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git /opt/depot_tools && \
    cd /opt/depot_tools && \
    patch -p1 -B .fix-depot-tools/ -i /tmp/fix-depot-tools.patch

RUN --mount=type=bind,source=patches/fix-gn.patch,dst=/tmp/fix-gn.patch \
    git clone https://gn.googlesource.com/gn /opt/gn && \
    cd /opt/gn && \
    patch -p1 -B .fix-gn/ -i /tmp/fix-gn.patch && \
    python3 build/gen.py && \
    ninja -j $(nproc) -C out

ENV PATH="/opt/depot_tools:/opt/gn/out:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
