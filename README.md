# Archlinux installer script

This install installer script will install [Archlinux](https://www.archlinux.org/) as I prefer it. Input options included in the script:

| Input | Description |
|---|---|
| DISK | Which disk to install on. |
| COUNTRY | Choose country. |
| KEYMAP | Keymap used. |
| HOST_NAME | Hostname to apply to install. |
| PASSWD | Password used for disk encryption and login. |
| USER | Username. |
| TIMEZONE | Current timezone. |

## Get started

Load the install media. And follow these steps

```bash
# Load keymap
loadkeys dk

# For wifi
iwctl station DEVICE connect SSID

# Check internet connection
ping https://wwww.archlinux.org/

# Find name of disk to install Archlinux on
lsblk

# Fetch install script
curl -o install.sh https://raw.githubusercontent.com/wcarlsen/archlinux-install/main/install.sh

# Change input variables to your liking
vim install.sh

# Make executable
chmod +x install.sh

# Run script
./install.sh

# Post install
exit
umount -a
reboot

# For wifi after reboot with no desktop environment
nmtui

# Use ansible to install the rest
sudo pacman -S ansible
yay -S ansible-aur-git

# First disable pacman password prompt when using yay (we will change it back later)
echo "YOUR_USERNAME ALL=(ALL) NOPASSWD: /usr/bin/pacman" | sudo tee /etc/sudoers.d/11-install-YOUR_USERNAME
visudo -cf /etc/sudoers.d/11-install-YOUR_USERNAME # Validate change

# Use ansible-pull to apply playbooks
ansible-pull -U https://github.com/wcarlsen/archlinux-install -i localhost, local.yml --ask-become

# Enable pacman password prompt
sudo rm /etc/sudoers.d/11-install-YOUR_USERNAME
```

## TODO

- [] Script Gnome settings (using "dconf watch /" might help)
- [] Setup xorg as default Gnome session