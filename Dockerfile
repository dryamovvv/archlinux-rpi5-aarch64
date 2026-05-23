FROM archlinux:latest

RUN pacman -Syu --noconfirm \
    arch-install-scripts \
    bash \
    dosfstools \
    e2fsprogs \
    parted \
    psmisc \
    qemu-user-static \
    shellcheck \
    sudo \
    systemd \
    util-linux

WORKDIR /workspace

ENTRYPOINT ["/bin/bash"]
