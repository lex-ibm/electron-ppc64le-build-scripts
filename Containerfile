FROM quay.io/almalinuxorg/almalinux:8.10

RUN dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm && \
    /usr/bin/crb enable && \
    dnf module enable -y nodejs:20 && \
    dnf install -y  alsa-lib-devel \
                    atk-devel \
                    bindgen-cli \
                    binutils-powerpc64le-linux-gnu \
                    bzip2-devel \
                    cpio \
                    clang \
                    clang-tools-extra \
                    cups-devel \
                    dbus-devel \
                    dbus-glib-devel \
                    desktop-file-utils \
                    double-conversion-devel \
                    elfutils \
                    elfutils-libelf-devel \
                    expat-devel \
                    flac-devel \
                    fontconfig-devel \
                    gcc-toolset-13-libatomic-devel \
                    git \
                    gperf \
                    glib2-devel \
                    glibc-devel \
                    highway-devel \
                    java-1.8.0-openjdk-headless \
                    kernel-headers \
                    lcms2-devel \
                    libXNVCtrl-devel \
                    libXdamage-devel \
                    libXtst-devel \
                    libappstream-glib \
                    libatomic \
                    libcap-devel \
                    libcurl-devel \
                    libdrm-devel \
                    libevdev-devel \
                    libffi-devel \
                    libgcrypt-devel \
                    libnotify-devel \
                    libpng-devel \
                    libsecret-devel \
                    libudev-devel \
                    libusb-devel \
                    libutempter-devel \
                    libuuid-devel \
                    libxshmfence-devel \
                    libxslt-devel \
                    llvm \
                    lld \
                    mesa-libGL-devel \
                    mesa-libgbm-devel \
                    ninja-build \
                    nodejs \
                    nss-devel \
                    opus-devel \
                    pam-devel \
                    patch \
                    pciutils-devel \
                    /usr/bin/pip-3.9 \
                    /usr/bin/python3.9 \
                    pulseaudio-libs-devel \
                    re2-devel \
                    rustc \
                    speech-dispatcher-devel \
                    systemd \
                    xz \
                    yarnpkg \
                    zlib-devel \
                    ; \
    pip-3.9 install httplib2 && \
    alternatives --set python /usr/bin/python3.9 && \
    alternatives --set python3 /usr/bin/python3.9 && \
    if [[ $(uname -m) != "ppc64le" ]]; then \
        cd /; \
        dnf makecache --forcearch=ppc64le; \
        dnf download --forcearch=ppc64le compiler-rt rust-std-static; \
        rpm2cpio compiler-rt-*.rpm | cpio -idmv './usr/lib/clang/18/lib/ppc64le-redhat-linux-gnu*'; \
        rpm2cpio rust-std-static-*.rpm | cpio -idmv './usr/lib/rustlib/powerpc64le-unknown-linux-gnu*'; \
        rm compiler-rt-*.rpm rust-std-static-*.rpm; \
    fi

RUN --mount=type=bind,source=patches/fix-depot-tools.patch,dst=/tmp/fix-depot-tools.patch \
    --mount=type=bind,source=patches/fix-gn.patch,dst=/tmp/fix-gn.patch \
    git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git /opt/depot_tools && \
    cd /opt/depot_tools && \
    patch -p1 -B .fix-depot-tools/ -i /tmp/fix-depot-tools.patch && \
    git clone https://gn.googlesource.com/gn /opt/gn && \
    cd /opt/gn && \
    patch -p1 -B .fix-gn/ -i /tmp/fix-gn.patch && \
    python3 build/gen.py && \
    ninja -j $(nproc) -C out

RUN ln -s /lib64/pkgconfig /usr/lib/pkgconfig && \
    dnf makecache --forcearch=$(uname -m) && \
    dnf install -y libxkbcommon-devel

ENV PATH="/opt/depot_tools:/opt/gn/out:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
