#!/bin/bash
set -e

WORK_DIR="$(mktemp --directory --tmpdir build-root.XXXXXXXX)"
trap 'rm -rf "${WORK_DIR}"' EXIT

if [ -f rootcache.tar.gz ]; then
  tar --extract --numeric-owner --gzip --file rootcache.tar.gz --directory "${WORK_DIR}" 
else
  debootstrap --variant=minbase --include=linux-image-amd64,ifupdown,openssh-server stretch "${WORK_DIR}" http://httpredir.debian.org/debian
  tar --create --numeric-owner --gzip --file rootcache.tar.gz --directory "${WORK_DIR}" .
fi


# Clean up file with misleading information from host
  rm "${WORK_DIR}/etc/hostname"

# Disable installation of recommended packages
  echo 'APT::Install-Recommends "false";' >"${WORK_DIR}/etc/apt/apt.conf.d/50norecommends"

# Configure networking
cat >>"${WORK_DIR}/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet dhcp
EOF
 
cat >>"${WORK_DIR}/etc/resolv.conf" <<'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF


# Set up initramfs for booting with squashfs+aufs
cat >> "${WORK_DIR}/etc/initramfs-tools/modules" <<'EOF'
squashfs
overlayfs
aufs
loop
EOF
#cat >"${WORK_DIR}/etc/initramfs-tools/scripts/init-bottom/aufs" <<'EOF'
##!/bin/sh -e
#case $1 in
#  prereqs)
#  exit 0
#  ;;
#esac
#mkdir /ro
#mkdir /rw
#mount -n -o mode=0755 -t tmpfs root-rw /rw
#mount -n -o move ${rootmnt} /ro
#mount -n -o dirs=/rw:/ro=ro -t aufs root-aufs ${rootmnt}
#mkdir ${rootmnt}/ro
#mkdir ${rootmnt}/rw
#mount -n -o move /ro ${rootmnt}/ro
#mount -n -o move /rw ${rootmnt}/rw
#EOF
cat >"${WORK_DIR}/etc/initramfs-tools/scripts/init-bottom/overlayfs" <<'EOF'
#!/bin/sh -e
case $1 in
  prereqs)
  exit 0
  ;;
esac
mkdir -p /userconf/{etc,work}
mount none -t overlayfs -o lowerdir=/etc,upperdir=/userconf/etc,workdir=/userconf/work /etc
EOF

cat >"${WORK_DIR}/etc/initramfs-tools/scripts/init-bottom/losetup" <<'EOF'
#!/bin/sh -e
losetup fw.squashfs /dev/loop0
export ROOT=/dev/loop0
EOF
#chmod +x "${WORK_DIR}/etc/initramfs-tools/scripts/init-bottom/aufs"
chmod +x "${WORK_DIR}/etc/initramfs-tools/scripts/init-bottom/overlayfs"
chroot "${WORK_DIR}" update-initramfs -u


# Clean up temporary files
rm -rf "${WORK_DIR}"/var/cache/apt/*


# Build the root filesystem image, and extract the accompanying kernel and initramfs
mksquashfs "${WORK_DIR}" fw.squashfs.new -noappend -e /boot; mv fw.squashfs.new fw.squashfs
cp -p "${WORK_DIR}/boot"/vmlinuz-* fw.vmlinuz.new; mv fw.vmlinuz.new fw.vmlinuz
cp -p "${WORK_DIR}/boot"/initrd.img-* fw.initrd.new; mv fw.initrd.new fw.initrd
