#!/bin/bash

#---help---
#
#---help---
set -eu

#----[ Functions ]----#
die() {
	printf '\033[1;31mERROR:\033[0m %s\n' "$@" >&2  # bold red
	exit 1
}

einfo() {
	printf '\n\033[1;36m> %s\033[0m\n' "$@" >&2  # bold cyan
}

ewarn() {
	printf '\033[1;33m> %s\033[0m\n' "$@" >&2  # bold yellow
}

usage() {
	sed -En '/^#---help---/,/^#---help---/p' "$0" | sed -E 's/^# ?//; 1d;$d;'
}

gen_chroot_script() {
cat <<-EOF
#!/bin/bash
set -e
mount --rbind /dev/ $DIR/dev
mount --rbind /dev/pts $DIR/dev/pts
mount --rbind /sys $DIR/sys
mount --rbind /proc $DIR/proc
chroot $DIR
	EOF
}

gen_chroot_script2() {
cat <<-EOF
#!/bin/bash
set -e
umount -l -f $DIR/proc/
umount -l -f $DIR/dev/
umount -l -f $DIR/sys/
#umount -l $DIR/dev/pts
	EOF
}

build_chroot() {
mount --rbind /dev/ $DIR/dev
mount --rbind /dev/pts $DIR/dev/pts
mount --rbind /sys $DIR/sys
mount -t proc none $DIR/proc
chroot $DIR  /debootstrap/debootstrap --second-stage
}
#----[ END ]----#

#----[ Variable Notation  ]----#
ARCH2=$(arch)
: ${ARCH:="arm64"}
: ${CODENAME:="jammy"}
: ${COMPONENT:="main"}
: ${DISTRO:="ubuntu"}
: ${MIRROR:="http://ports.ubuntu.com/ubuntu-ports"}
: ${VARIANT:="minbase"}
: ${DIR:="$DISTRO-$ARCH-$VARIANT-chroot"}
while getopts ":a:c:co:d:h:m:v:" OPTION; do
        case "${OPTION}" in
	a) ARCH=${OPTARG} ;;
        c) CODENAME=${OPTARG} ;;
	co) COMPONENT=${OPTARG} ;;
	d) DIR=${OPTARG} ;;
        h | --help) usage; exit 0;;
	m) MIRROR=${OPTARG} ;;
	v) VARIANT=${OPTARG} ;;
        esac
done
#----[ END ]----#

#----[ First Stage Build  ]----#
if [ "$(id -u)" -ne 0 ]; then
	die 'This script must be run as root!'
fi

apt install debootstrap -y

gen_chroot_script > enter-chroot
gen_chroot_script2 > unmount-chroot
chmod +x enter-chroot unmount-chroot

#mkdir $DIR
debootstrap --arch=$ARCH --variant=$VARIANT --foreign $CODENAME $DIR $MIRROR
#----[ END  ]----#

#----[ QEMU addons ]----#
#echo ""
einfo "QEMU is used"
echo ""
#apt install binfmt-support qemu-user-static -y
#cp /usr/bin/qemu-$ARCH-static $DIR/usr/bin
#update-binfmts --enable qemu-$ARCH
#----[ END ]----#

#----[ Second Stage Build  ]----#
build_chroot
./unmount-chroot

du -sh $DIR

cat <<EOF > sources.list
deb $MIRROR $CODENAME $COMPONENT
deb-src $MIRROR $CODENAME $COMPONENT

deb $MIRROR $CODENAME-updates $COMPONENT
deb-src $MIRROR $CODENAME-updates $COMPONENT
EOF
mv sources.list $DIR/etc/apt/

./enter-chroot <<-EOF
unset ANDROID_ART_ROOT
unset ANDROID_DATA
unset ANDROID_ROOT
unset LD_PRELOAD
unset PREFIX
unset TMPDIR

export HOME=/root
export LC_ALL=C
echo "$DISTRO-$ARCH-$VARIANT-chroot" > /etc/hostname
apt-get update
apt-get install sudo -y
EOF
./unmount-chroot
du -sh $DIR
#----[ END  ]----#
