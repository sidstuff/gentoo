# Variables

if (( $# == 3 )); then
    DEVICE=$3
else
    DEVICE=$(lsblk -dapx SIZE | awk '{w=$1} END{print w}')
fi

RAM=$(free -g | grep Mem: | awk '{print $2}')GiB

ARCH=$(lscpu | awk '/Architecture/{print $2}')
GUID="0FC63DAF-8483-4772-8E79-3D69D8477DE4"
case $ARCH in
    x86_64)  ARCH="amd64"
             GUID="4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709"
             ;;
    aarch64) ARCH="arm64"
             GUID="B921B045-1DF0-41C3-AF44-4C6F280D3FAE"
             ;;
    riscv64) ARCH="riscv"
             GUID="72EC70A6-CF74-40E6-BD49-4BDA08E8F224"
             ;;
esac

GPUS=$(lspci | grep 'VGA\|Display')
if [[ $GPUS =~ "Intel" ]]; then
  INTEL="intel"
fi
if [[ $GPUS =~ "Advanced Micro Devices" ]]; then
  AMD="amdgpu radeonsi"
fi
if [[ $GPUS =~ "NVIDIA" ]]; then
  NVIDIA="nvidia"
fi
VIDEO_CARDS=$(echo "$INTEL $AMD $NVIDIA" | awk '{$1=$1};1')

# Disk formatting

case $DEVICE in
    /dev/nvme*) nvme format -f -s 1 $DEVICE
                ;;
    /dev/sd*) hdparm --security-set-pass NULL $DEVICE
              hdparm --security-erase NULL $DEVICE
              ;;
    *) shred --verbose --random-source /dev/urandom --iterations 1 $DEVICE
esac

sfdisk -X gpt $DEVICE << EOF
,1GiB,U
,,$GUID
EOF

readarray -t PART < <(lsblk -lp $DEVICE | tail -n2 | awk '{print $1}')

printf $2 | cryptsetup luksFormat -s 512 ${PART[1]} -
printf $2 | cryptsetup luksOpen --allow-discards -d - ${PART[1]} root
mkfs.fat -F 32 ${PART[0]}
mkfs.btrfs /dev/mapper/root

for i in {0..2}
do
  UUID[i]=$(blkid ${PART[i]} -s UUID -o value)
done
ROOTUUID=$(blkid /dev/mapper/root -s UUID -o value)

mount /dev/mapper/root /mnt/gentoo
cd /mnt/gentoo

# Swap

btrfs subvolume create swap_vol
chattr +C swap_vol
fallocate -l $RAM swap_vol/swapfile
chmod 600 swap_vol/swapfile
mkswap swap_vol/swapfile
swapon swap_vol/swapfile

# Gentoo

wget -r -l1 -np -nd "https://distfiles.gentoo.org/releases/$ARCH/autobuilds/current-stage3-$ARCH-desktop-openrc/" -A "*.tar.xz"
tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
rm -f stage3-*.tar.xz

# Dracut

cat > etc/dracut.conf << EOF
add_dracutmodules+=" crypt dm rootfs-block "
kernel_cmdline+=" root=UUID=$ROOTUUID rd.luks.uuid=${UUID[1]} "
EOF

# Filesystem table

cat > etc/fstab << EOF
UUID=${UUID[0]}     /efi   vfat   noatime          0  1
UUID=$ROOTUUID      /      btrfs  noatime,discard  0  0
/swap_vol/swapfile  none   swap   sw               0  0
EOF

# Chroot

cp --dereference /etc/resolv.conf etc/
arch-chroot . << EOF
source /etc/profile
mkdir /efi
mount ${PART[0]} /efi
curl -s https://raw.githubusercontent.com/sidstuff/gentoo/master/start.sh | bash -s $1 $2 $DEVICE $VIDEO_CARDS
EOF
cd /
umount -R /mnt/gentoo
shutdown -hP now
