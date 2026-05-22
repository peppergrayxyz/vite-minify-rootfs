#!/usr/bin/env bash
set -euo pipefail

#
# test env to replicate Error: [lightningcss minify] Cannot find module '../lightningcss.linux-arm64-musl.node'
#

stage3="stage3-arm64-musl-llvm-openrc"
stage3url="https://distfiles.gentoo.org/releases/arm64/autobuilds/current-$stage3"
stage3info="latest-$stage3.txt"

rootfs="rootfs"
socket="$rootfs.sock"
mem="2G"
run_log="$rootfs.log"
qemu_monitor_socket="${rootfs}_mon.sock"

podman_run() {
    podman run -it --arch arm64 --cgroups=disabled --user root --rootfs "$(pwd)/$rootfs" "$@"
}

#
# setup rootfs
#
if [ ! -f "$rootfs/setup.done" ]; then

    mkdir -p "$rootfs"

    stage3file="$(curl -fsSL $stage3url/$stage3info \
        | awk '/\.tar\.xz([[:space:]]|$)/ {print $1; exit}' \
        | xargs -n1 basename)"

    wget -nc "$stage3url/$stage3file"
    wget -nc "$stage3url/$stage3file.sha256"
    sha256sum --check "$stage3file.sha256"

    tar xvpf "$stage3file" --skip-old-files --xattrs-include='*.*' --numeric-owner --exclude='./dev/*' -C "$rootfs"

    cp --dereference /etc/resolv.conf "$rootfs/etc"

    cat >>"$rootfs/etc/portage/make.conf" <<-EOL
		ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE"
		FEATURES="-ipc-sandbox -network-sandbox -pid-sandbox"
		EOL

    cat >>"$rootfs/etc/portage/package.accept_keywords/nodejs" <<-EOL
		llvm-runtimes/libatomic-stub **
		EOL
    
    cat >"$rootfs/setup.sh" <<-EOL
		#!/usr/bin/env bash
		set -euo pipefail
		
		emerge-webrsync
		emerge --sync
		eselect news read
		getuto

		emerge llvm-runtimes/libatomic-stub
		emerge net-libs/nodejs

		npm install -g npm@11.15.0

		date > "setup.done"
		exit 0
		EOL

    cat >"$rootfs/build.sh" <<-EOL
		#!/bin/sh
		. /etc/profile
		cd /home
		if [ ! -d "my-app" ]; then
			npm create vite@latest my-app --yes -- --template vue-ts --no-interactive
			npm --prefix my-app install
		fi
		cd my-app
		npm run build
		EOL
    
    chmod +x "$rootfs/setup.sh" "$rootfs/build.sh"

    podman_run "./setup.sh"
fi

#
# build the project
#
podman_run "./build.sh"