# Variables

GOARCH=$(lscpu | awk '/Architecture/{print $2}')
case $GOARCH in
    x86_64) ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    riscv64) ARCH="riscv64" ;;
esac
ZNVER=$(gcc -v -E -x c /dev/null -o /dev/null -march=native 2>&1 | grep -o mtune=znver[0-9])
RAMBY2=$(($(free --giga | grep Mem | awk '{print $2}')/2))
NPROC=$(nproc)

# Packages

emerge-webrsync
eselect profile set $(eselect profile list | grep '[0-9]/desktop/plasma (stable)' | awk -F '[][]' '{print $2}')

curl https://ipapi.co/timezone > /etc/timezone

mkdir /etc/portage/env
echo "x11-misc/sddm sddm_initial_vt.conf" >> /etc/portage/package.env
echo "SDDM_INITIAL_VT=7" > /etc/portage/env/sddm_initial_vt.conf

emerge -1 app-portage/cpuid2cpuflags
echo "*/* $(cpuid2cpuflags)" > /etc/portage/package.use/00cpu-flags
echo "sys-kernel/installkernel grub dracut" > /etc/portage/package.use/installkernel
echo "www-client/firefox hwaccel" > /etc/portage/package.use/firefox

emerge -1 app-portage/mirrorselect
mirrorselect -i -o > /etc/portage/make.conf
echo "VIDEO_CARDS=\"$4\"" >> /etc/portage/make.conf
echo "MAKEOPTS=\"-j$((RAMBY2 < NPROC ? RAMBY2 : NPROC)) -l$((NPROC+1))\"" >> /etc/portage/make.conf
curl -s https://raw.githubusercontent.com/sidstuff/gentoo/master/make.conf >> /etc/portage/make.conf
echo "GOARCH=$GOARCH" >> /etc/portage/make.conf
curl -s https://raw.githubusercontent.com/sidstuff/gentoo/master/world >> /var/lib/portage/world
if [ $ARCH = "amd64" ]; then
  if [ $(lscpu | awk '/Vendor ID/{print $3}') = "GenuineIntel" ]; then
    echo "GOAMD64=v4" >> /etc/portage/make.conf
    echo "sys-firmware/intel-microcode" >> /var/lib/portage/world
  elif [[ $ZNVER =~ ["4"|"5"] ]]; then
   echo "GOAMD64=v4" >> /etc/portage/make.conf
  else
   echo "GOAMD64=v3" >> /etc/portage/make.conf
  fi
fi

emerge -1f sys-kernel/gentoo-kernel
emerge -uDN --autounmask=y --autounmask-continue @world   # emerge will fetch all packages parallel to the compilation,
emerge -c                                                 # thus no internet is required during most of the emerge and for the rest of the install.

# Locale and time

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
eselect locale set en_US.UTF-8
env-update && source /etc/profile

emerge --config sys-libs/timezone-data

cat > /etc/conf.d/hwclock << EOF
clock_hctosys="YES" 
clock_systohc="YES"
clock="local"
EOF
rc-update add chronyd default

# Secure Boot

mkdir /etc/certs
cd /etc/certs
openssl req -new -nodes -utf8 -sha256 -x509 -days 36500 -outform PEM -subj "/CN=Kernel signing key" -out kernel_key.pem -keyout kernel_key.pem
openssl x509 -in kernel_key.pem -inform PEM -out kernel_key.der -outform DER
chmod 600 kernel_key.der

cp /usr/share/shim/BOOTX64.EFI /efi/EFI/Gentoo/shimx64.efi
cp /usr/share/shim/mmx64.efi /efi/EFI/Gentoo/mmx64.efi
cp /usr/lib/grub/grub-x86_64.efi.signed /efi/EFI/Gentoo/grubx64.efi
mokutil --import /etc/certs/kernel_key.der
efibootmgr -c -d $3 -l '\EFI\Gentoo\shimx64.efi' -L 'GRUB via Shim' -u
echo "GRUB_CFG=/efi/EFI/Gentoo/grub.cfg" > /etc/env.d/99grub
env-update

# Boot

sed -i 's/^#\?rc_parallel.*/rc_parallel="YES"/' /etc/rc.conf
plymouth-set-default-theme solar
grub-install --efi-directory=/efi
cat > /etc/default/grub << EOF
GRUB_TIMEOUT=0
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_GFXPAYLOAD_LINUX=keep
EOF
if [[ $DEVICE =~ "/dev/nvme" ]]; then echo "GRUB_CMDLINE_LINUX=\"rd.luks.allow-discards\"" >> /etc/default/grub; fi
emerge sys-kernel/gentoo-kernel   # installkernel will run grub-mkconfig and generate grub.cfg, as well as an initramfs using dracut

# Display Manager

rc-update add elogind boot
rc-update add display-manager default
cat > /etc/conf.d/display-manager << EOF
CHECKVT=7
DISPLAYMANAGER="sddm"
EOF

cat > /etc/sddm.conf.d/override.conf << EOF
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1
EOF

# User(s)

mkdir /etc/sudoers.d
echo "%wheel ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/sudoers
useradd -m -G users,wheel,audio,video -s /bin/bash $1
echo -e "root:$2\n$1:$2" | chpasswd

# Networking

echo "$1" > /etc/hostname
rc-update add dhcpcd default

# Wireless

cat > /etc/wpa_supplicant/wpa_supplicant.conf << EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel
update_config=1
EOF
cat > /etc/conf.d/wpa_supplicant << EOF
# uncomment this if wpa_supplicant starts up before your network interface is ready and it causes issues
# rc_want="dev-settle"
wpa_supplicant_args="-B -M -c /etc/wpa_supplicant/wpa_supplicant.conf"
EOF
rc-update add wpa_supplicant default

# Add update script

cd /home/$1/Desktop
cat > update.sh << EOF
sudo su
chvt 6
emaint -a sync
emerge -uDU @world
emerge -c
shutdown -hP now
EOF
chmod +x update.sh
