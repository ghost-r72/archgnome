#!/bin/bash

# Drive to install to.
disk="/dev/sda"

# Desired SWAP size
swap_size="4"

# System timezone.
continent_city="Asia/Kolkata"

# Hostname of the installed machine.
hostname="archlinux"

# Root password
root_password="arch"

# Main user to create (by default, added to wheel group).
username="arch"

# The main user's password
user_password="arch"

# Set different microcode, kernel params and initramfs modules according to CPU vendor
cpu_vendor=$(cat /proc/cpuinfo | grep vendor | uniq)
cpu_microcode=""
if [[ $cpu_vendor =~ "AuthenticAMD" ]]
then
 cpu_microcode="amd-ucode"
elif [[ $cpu_vendor =~ "GenuineIntel" ]]
then
 cpu_microcode="intel-ucode"
fi

echo "Updating system clock"
timedatectl set-ntp true

echo "Syncing packages database"
pacman -Sy --noconfirm

echo "Wiping drive"
sgdisk --zap-all ${disk}

echo "Creating partition"
sgdisk -n 1:0:+1000M ${disk} # partition 1 (BOOT), default start block, 512MB
sgdisk -n 2:0:+"$swap_size"G ${disk} # partition 2(Swap), default start block, desired size
sgdisk -n 3:0:0 ${disk} # partition 3 (Root), default start, remaining

echo "Setting partition types"
sgdisk -t 1:ef00 ${disk}
sgdisk -t 2:8200 ${disk}
sgdisk -t 3:8300 ${disk}

echo "Setting up root partition"
yes | mkfs.ext4 ${disk}3
mount ${disk}3 /mnt

echo "Setting up boot partition"
mkfs.fat -F32 ${disk}1
mkdir /mnt/boot
mount ${disk}1 /mnt/boot

echo "Setting up swap"
mkswap ${disk}2
swapon ${disk}2

echo "Installing Arch Linux"
pacstrap /mnt base linux linux-firmware vim $cpu_microcode

echo "Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

echo "Configuring new system"
arch-chroot /mnt /bin/bash << EOF
echo "Setting system clock"
timedatectl set-ntp true
timedatectl set-timezone $continent_city
hwclock --systohc --localtime

echo "Setting locales"
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf
locale-gen

echo "Adding persistent keymap"
echo "KEYMAP=us" > /etc/vconsole.conf

echo "Setting hostname"
echo $hostname >> /etc/hostname
echo "127.0.0.1     localhost" >> /etc/hosts
echo "::1           localhost" >> /etc/hosts
echo "127.0.1.1     $hostname.localdomain   $hostname" >> /etc/hosts

echo "Setting root password"
echo -en "$root_password\n$root_password" | passwd

echo "Installing packages"
pacman -S --noconfirm base-devel grub efibootmgr networkmanager wget git man-db man-pages diffutils dialog wpa_supplicant linux-headers mtools alsa-utils pulseaudio dosfstools

echo "Configuring grub"
grub-install --target=x86_64-efi --efi-directory=/boot/ --bootloader-id=ArchLinux
grub-mkconfig -o /boot/grub/grub.cfg

echo "Setting swappiness to 20"
touch /etc/sysctl.d/swappiness.conf
echo 'vm.swappiness=20' > /etc/sysctl.d/swappiness.conf

echo "Enabling periodic TRIM"
systemctl enable fstrim.timer

echo "Enabling NetworkManager"
systemctl enable NetworkManager

echo "Creating new user"
useradd -m -G wheel,video,audio $username
echo -en "$user_password\n$user_password" | passwd $username

echo "Adding user as a sudoer"
echo '%wheel ALL=(ALL) ALL' | EDITOR='tee -a' visudo
EOF

umount -R /mnt
swapoff -a

echo -e "\nArch Linux is ready!\n"


echo "--------------------------------------"
echo "--          Please Reboot           --"
echo "--------------------------------------"