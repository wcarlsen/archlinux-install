#!/bin/bash

set -exo pipefail

# Configuration
DISK="/dev/nvme0n1"
COUNTRY="Denmark"
KEYMAP="dk"
HOST_NAME="archlinux"
PASSWD="So Much Secret" # pragma: allowlist secret
USER="wcarlsen"
GITHUB_USER="wcarlsen" # user for ssh config
TIMEZONE="Europe/Copenhagen"
DESKTOP="gnome"
ENABLE_ENCRYPTION=true

# Main setup
setup() {
    system_clock
    create_mirrorlist
    zap_disk
    partition_disk
    encrypt_main_partition
    create_volumes
    format_partitions
    mount_file_system
    install_base
    chroot
}

# Chroot setup
chrootsetup() {
    timezone
    localization
    network_configuration
    set_root_passwd
    install_packages
    initramfs
    bootloader
    add_user
    video_driver
    install_desktop
    prepare_yay
    configure_ssh
    enable_services
    # ansible_post_install
    rm /root/install.sh
    exit 0
}

# Update system clock
system_clock() {
    echo "Update system clock"
    timedatectl set-ntp true
}

# Create mirrorlist
create_mirrorlist() {
    echo "Creating mirrorlist"
    pacman -Syy --noconfirm python reflector
    reflector -c $COUNTRY --protocol https -a 6 --sort rate --save /etc/pacman.d/mirrorlist
    pacman -Syyy
}

# Zap disk
zap_disk() {
    echo "Zapping disk ${DISK}"
    sgdisk --zap-all $DISK
}

# Parition disk
partition_disk() {
    echo "Partion disk ${DISK}"
    sgdisk -n 0:0:+260M -t 0:ef00 $DISK
    sgdisk -n 0:0:0 -t 0:8e00 $DISK

    UEFI_PARTITION=$(fdisk -l $DISK | grep 'EFI' | awk '{print $1}')
    MAIN_PARTITION=$(fdisk -l $DISK | grep 'LVM' | awk '{print $1}')
}


# Encrypt main partition
encrypt_main_partition() {
    if [[ $ENABLE_ENCRYPTION == true ]]; then
        echo "Encrypt main partition"
        echo -n "${PASSWD}" | cryptsetup luksFormat "$MAIN_PARTITION" -
        echo -n "${PASSWD}" | cryptsetup open "$MAIN_PARTITION" cryptlvm -
    fi
}

# Create physical and logical volumes
create_volumes() {
    echo "Create volumes"
    if [[ $ENABLE_ENCRYPTION == true ]]; then
        pvcreate /dev/mapper/cryptlvm
        vgcreate vg1 /dev/mapper/cryptlvm
    else
        pvcreate "$MAIN_PARTITION"
        vgcreate vg1 "$MAIN_PARTITION"
    fi
    lvcreate -L 40G vg1 -n root
    lvcreate -L 2G vg1 -n swap
    lvcreate -l 100%FREE vg1 -n home
}

# Format partitions
format_partitions() {
    echo "Format partitions"
    mkfs.fat -F32 "$UEFI_PARTITION"
    mkfs.ext4 /dev/vg1/root
    mkfs.ext4 /dev/vg1/home
    mkswap /dev/vg1/swap
}

# Mount file system
mount_file_system() {
    echo "Mount file system"
    mount /dev/vg1/root /mnt
    mkdir /mnt/home
    mount /dev/vg1/home /mnt/home
    mkdir /mnt/boot
    mount "$UEFI_PARTITION" /mnt/boot
    swapon /dev/vg1/swap
}

# Install base
install_base() {
    echo "Install base"
    # Pacstrap
    pacstrap /mnt base linux linux-firmware intel-ucode lvm2

    # Generate filesystem table
    genfstab -U /mnt >> /mnt/etc/fstab
}

# Configure system
chroot() {
    echo "Configure system"
    cp install.sh /mnt/root/install.sh
    chmod +x /mnt/root/install.sh
    arch-chroot /mnt /root/install.sh setupchroot
}

# Timezone
timezone() {
    echo "Timezone"
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    hwclock --systohc
}

# Localization
localization() {
    echo "Localization"
    echo "" >> /etc/locale.gen
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" >> /etc/locale.conf
    echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
}

# Network configuration
network_configuration() {
    echo "Network configuration"
    echo "$HOST_NAME" > /etc/hostname
    {
        echo ""
        echo "127.0.0.1     localhost"
        echo "::1           localhost"
        echo "127.0.1.1     ${HOST_NAME}.localdomain   ${HOST_NAME}"
    } >> /etc/hosts
}

# Set root password
set_root_passwd() {
    echo "Set root password"
    echo -n "root:${PASSWD}" | chpasswd
}

# Install packages
install_packages() {
    echo "Install packages"
    pacman -Sy --noconfirm grub efibootmgr networkmanager network-manager-applet wireless_tools wpa_supplicant dialog mtools dosfstools base-devel linux-headers git reflector bluez bluez-utils pulseaudio-bluetooth cups xdg-utils xdg-user-dirs jq openssh tlp
}

# Initramfs
initramfs() {
    echo "Initramfs"
    HOOKS=$(grep "^HOOKS=(" < /etc/mkinitcpio.conf)
    MOD_HOOKS=""
    for i in $HOOKS
    do
        if [[ "$i" == "autodetect" ]]; then
            HOOK="$i keymap"
        elif [[ "$i" == "filesystems" ]]; then
            if [[ $ENABLE_ENCRYPTION == true ]]; then
                HOOK="encrypt lvm2 $i"
            else
                HOOK="lvm2 $i"
            fi
        else
            HOOK="$i"
        fi
        MOD_HOOKS="${MOD_HOOKS} ${HOOK}"
    done
    MOD_HOOKS=${MOD_HOOKS:1}

    sed -i "s/^HOOKS=(.*/${MOD_HOOKS}/g" /etc/mkinitcpio.conf

    mkinitcpio -p linux
}

# Install bootloader
bootloader() {
    echo "Install bootloader"
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    MAIN_PARTITION=$(fdisk -l $DISK | grep 'LVM' | awk '{print $1}')
    MAIN_PARTITION_UUID=$(blkid | grep "$MAIN_PARTITION" | awk '{print $2}')
    GRUB_CMD="cryptdevice=${MAIN_PARTITION_UUID}:cryptlvm root=\/dev\/vg1\/root"
    if [[ $ENABLE_ENCRYPTION == true ]]; then
        sed -i "s/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"${GRUB_CMD}\"/g" /etc/default/grub
    fi
    grub-mkconfig -o /boot/grub/grub.cfg
}

# Add user
add_user() {
    echo "Add user"
    useradd -mG wheel $USER
    echo -n "${USER}:${PASSWD}" | chpasswd
    sed -i "s/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/" /etc/sudoers
}

# Video driver
video_driver() {
    echo "Install video driver"
    pacman -Sy --noconfirm xf86-video-intel
    if lspci | grep -q 'NVIDIA'; then
        pacman -Sy --noconfirm nvidia nvidia-utils nvidia-settings nvidia-prime
    fi
}

# Desktop
install_desktop() {
    echo "Install desktop and display server"
    case $DESKTOP in
        "gnome")
            pacman -Sy --noconfirm xorg gnome gnome-tweaks
            systemctl enable gdm
            ;;
        "kde")
            pacman -Sy --noconfirm plasma kde-applications sddm
            systemctl enable sddm
            ;;
        "dwm")
            pacman -Sy --noconfirm xorg xorg-xinit dmenu
            su - $USER -c "git clone git://git.suckless.org/dwm /home/$USER/suckless/dwm"
            su - $USER -c "git clone git://git.suckless.org/st /home/$USER/suckless/st"
            su - $USER -c "git clone git://git.suckless.org/slock /home/$USER/suckless/slock"
            su - $USER -c "make -C /home/$USER/suckless/dwm/ && echo $PASSWD | sudo -S make -C /home/$USER/suckless/dwm/ clean install"
            su - $USER -c "make -C /home/$USER/suckless/st/ && echo $PASSWD | sudo -S make -C /home/$USER/suckless/st/ clean install"
            su - $USER -c "make -C /home/$USER/suckless/slock/ && echo $PASSWD | sudo -S make -C /home/$USER/suckless/slock/ clean install"
            su - $USER -c "echo 'setxkbmap $KEYMAP; exec dwm' > /home/$USER/.xinitrc"
            ;;
        "exwm")
            pacman -Sy --noconfirm xorg xorg-xinit emacs
            su - $USER -c "echo 'setxkbmap $KEYMAP; exec emacs' > /home/$USER/.xinitrc"
            ;;
        *)
            echo 'No valid desktop specified'
            ;;
    esac
}

# Yay
prepare_yay() {
    echo "Prepare for yay"
    su - $USER -c "git clone https://aur.archlinux.org/yay.git /home/$USER/yay"
    echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/pacman" > /etc/sudoers.d/11-install-$USER
    visudo -cf /etc/sudoers.d/11-install-$USER
    su - wcarlsen -c "(cd /home/$USER/yay && makepkg -si --noconfirm)"
    rm -rf /home/$USER/yay
    rm /etc/sudoers.d/11-install-$USER
}

# Ssh
configure_ssh() {
    echo "Setting up ssh with github key"
    su - $USER -c "mkdir /home/$USER/.ssh && touch /home/$USER/.ssh/authorized_keys"
    curl https://api.github.com/users/$GITHUB_USER/keys | jq --arg GITHUB_USER "$GITHUB_USER" '(.[] | .key + " " + $GITHUB_USER + "@github/" + (.id|tostring))' | tr -d '"' > /home/$USER/.ssh/authorized_keys
    chown $USER:$USER /home/$USER/.ssh/authorized_keys
    chmod 0600 /home/$USER/.ssh/authorized_keys
    {
        echo "PasswordAuthentication no"
        echo "PubkeyAuthentication yes"
        echo "PermitRootLogin no"
    } >> /etc/ssh/sshd_config
}

# Enable services
enable_services() {
    echo "Enable services"
    systemctl enable NetworkManager
    systemctl enable bluetooth
    systemctl enable cups.service
    systemctl enable sshd
    systemctl enable tlp.service
}

if [[ $1 == setupchroot ]]; then
    chrootsetup
else
    setup
fi
