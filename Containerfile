FROM --platform=linux/ppc64le quay.io/almalinuxorg/almalinux:8.10 AS sysroot

RUN dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm && \
    /usr/bin/crb enable && \
    dnf install -y  alsa-lib-devel \
                    atk-devel \
                    cups-devel \
                    dbus-devel \
                    desktop-file-utils \
                    expat-devel \
                    fontconfig-devel \
                    glib2-devel \
                    glibc-devel \
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
                    mesa-libgbm-devel \
                    nss-devel \
                    pciutils-devel \
                    pulseaudio-libs-devel \
                    libappstream-glib \
                    bzip2-devel \
                    dbus-glib-devel \
                    elfutils-libelf-devel \
                    kernel-headers \
                    libffi-devel \
                    libxshmfence-devel \
                    mesa-libGL-devel \
                    "pkgconfig(gtk+-3.0)" \
                    re2-devel \
                    speech-dispatcher-devel \
                    zlib-devel \
                    pam-devel \
                    systemd \
                    libevdev-devel \
                    libpng-devel \
                    libnotify-devel \
                    gcc-toolset-13-libatomic-devel \
                    opus-devel \
                    flac-devel \
                    libsecret-devel \
                    lcms2-devel \
                    libxslt-devel \
                    highway-devel \
                    libXNVCtrl-devel \
                    double-conversion-devel \
                    libevent-devel

FROM quay.io/almalinuxorg/almalinux:8.10

RUN dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm && \
    /usr/bin/crb enable && \
    dnf module enable -y nodejs:20 && \
    dnf install -y  clang \
                    clang-tools-extra \
                    llvm \
                    lld \
                    rustc \
                    bindgen-cli \
                    /usr/bin/python3.9 \
                    /usr/bin/pip-3.9 \
                    ninja-build \
                    java-1.8.0-openjdk-headless \
                    xz \
                    patch \
                    nodejs \
                    yarnpkg \
                    binutils-powerpc64le-linux-gnu \
                    git \
                    elfutils \
                    cpio \
                    gperf \
                    opus-devel \
                    flac-devel \
                    libsecret-devel \
                    lcms2-devel \
                    libxslt-devel \
                    highway-devel \
                    libXNVCtrl-devel \
                    double-conversion-devel \
                    libevent-devel; \
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

COPY --from=sysroot / /sysroot

RUN rm -rf /sysroot/lib /sysroot/lib64 /sysroot/bin /sysroot/sbin && \
    ln -s /sysroot/usr/lib /sysroot/lib && \
    ln -s /sysroot/usr/lib64 /sysroot/lib64 && \
    ln -s /sysroot/usr/bin /sysroot/bin && \
    ln -s /sysroot/usr/sbin /sysroot/sbin && \
    ln -s /sysroot/usr/lib64/pkgconfig /sysroot/usr/lib/pkgconfig && \
    ln -s /lib64/pkgconfig /usr/lib/pkgconfig

ENV PATH="/opt/depot_tools:/opt/gn/out:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
