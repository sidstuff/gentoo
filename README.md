# Gentoo install script (disk encryption + secure boot)

## Usage

> [!WARNING]
> This script makes some assumptions about features supported by your hardware without actually checking for said support, so if not using it on a modern computer, go through the script and ensure everything is compatible with your hardware.

Plug in the USB drive you want to boot from during the installation. Run `lsblk` and find its device name, say `/dev/sda`. We're going to write a minimal Gentoo ISO onto it, so any data on it will be deleted/overwritten.

> [!NOTE]
> All scripts/commands henceforth are to be run as root.

To do so, run
```
curl -s https://raw.githubusercontent.com/sidstuff/gentoo/master/flash.sh | bash -s /dev/sda
```
Enter the BIOS and disable secure boot, as well as change the boot order so that the external bootable media (CD/DVD disks or USB drives) are tried before the internal disk devices, then reboot.

Once booted into the Gentoo live environment, connect to the internet. Unauthenticated Ethernet connections will work automatically.

For WPA-P Wi-Fi networks, run `wpa_passphrase ssid password >> /etc/wpa_supplicant/wpa_supplicant.conf` to add your network. See other configuration options [here](https://w1.fi/cgit/hostap/tree/wpa_supplicant/wpa_supplicant.conf). Start wpa_supplicant by running `/etc/init.d/wpa_supplicant start`.

For authenticated networks with captive portals featuring just an HTML form, download the login page via `wget anyurl.com`, inspect the html, and submit the required values via `curl` – see [these](https://stackoverflow.com/a/25095704) [posts](https://superuser.com/a/262795).

Now run
```
curl -s https://raw.githubusercontent.com/sidstuff/gentoo/master/start.sh | bash -s username password /dev/nvme0n1
```
The last argument is the storage device you want to install Gentoo onto, and can be omitted if okay with the default choice of the largest connected storage device.

Once the install is complete, the system will shut down. When you power it on again, enter the BIOS, and reorder its entries to boot from the disk, as well as re-enable secure boot.

Restart the computer and enjoy your new Gentoo system! Make sure you remember to regularly run the script `update.sh` (which will have been added to your Desktop) to keep your system updated.

## Choices made

* OpenRC
* dist-kernel
* btrfs
* swapfile the size of your RAM (TODO: hibernation)
* chroynd
* GRUB
* dracut
* plymouth (theme solar)
* Wayland
* SDDM
* KDE
* Firefox
* en_US.UTF-8

TODO: GPU support (currently just adds `nvidia`, `amdgpu radeonsi`, and/or `intel` to the `VIDEO_CARDS` variable, if you have a GPU from NVIDIA, AMD, and/or Intel, respectively, without even checking for compatibility)
