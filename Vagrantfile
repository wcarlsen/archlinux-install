Vagrant.configure("2") do |config|
  config.vm.box = "archlinux/archlinux"
  config.vm.network "private_network", ip: "172.42.42.100"
  config.vm.provider "virtualbox" do |vb|
    vb.name = "archlinux"
    vb.memory = "1024"
    vb.cpus = "1"
  end
  config.vm.provision "shell", privileged: false, inline: <<-SHELL
sudo pacman -Syy --needed --noconfirm git base-devel
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -rsi --needed --noconfirm
# yay -S ansible-aur-git
SHELL
end