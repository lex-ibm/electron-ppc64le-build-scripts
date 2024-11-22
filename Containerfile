FROM registry.access.redhat.com/ubi8/ubi:8.10

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
                    cpio; \
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

# Due to the EULA of UBI and my wanting to stick to RHEL as much as possible, I'm using AlmaLinux's PowerTools repo only for some packages (my Frankenstein's monster)
COPY --from=quay.io/almalinuxorg/almalinux:8.10 /etc/yum.repos.d/almalinux-powertools.repo /etc/yum.repos.d/almalinux-powertools.repo
COPY --from=quay.io/almalinuxorg/almalinux:8.10 /etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux /etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux
RUN dnf install -y --enablerepo=powertools gperf

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

ENV PATH="/opt/depot_tools:/opt/gn/out:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
