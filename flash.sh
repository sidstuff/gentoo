ARCH=$(lscpu | awk '/Architecture/{print $2}')
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    riscv64) ARCH="riscv" ;;
esac

wget -r -l1 -np -nd "https://distfiles.gentoo.org/releases/$ARCH/autobuilds/current-install-amd64-minimal/" -A "*.iso"
dd bs=4M if=$(find install-*.iso) of=$1 conv=fdatasync status=progress
reboot
