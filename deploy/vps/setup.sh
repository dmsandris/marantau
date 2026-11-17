#!/usr/bin/env bash
# Pengamanan & persiapan VM Marantau (Ubuntu 24.04). Aman diulang (idempotent).
# Dijalankan oleh .github/workflows/vps-setup.yml lewat SSH:  sudo bash setup.sh <user>
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

APP_USER="${1:?pakai: setup.sh <user>}"
step() { echo; echo "==> $*"; }

[ "$(id -u)" = 0 ] || { echo "harus root (sudo)"; exit 1; }
id "$APP_USER" >/dev/null 2>&1 || { echo "user $APP_USER tidak ada"; exit 1; }
[ -s "/home/$APP_USER/.ssh/authorized_keys" ] || { echo "authorized_keys $APP_USER kosong - batal (bisa terkunci)"; exit 1; }

step "Zona waktu & paket dasar"
timedatectl set-timezone Asia/Jakarta
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg ufw fail2ban unattended-upgrades \
  apt-listchanges age rclone postgresql-client jq htop ncdu >/dev/null

step "Patch keamanan otomatis"
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
cat >/etc/apt/apt.conf.d/52marantau-upgrades <<'EOF'
// Reboot otomatis bila kernel diperbarui, jam sepi (04:30 WIB).
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:30";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
systemctl enable --now unattended-upgrades >/dev/null

step "SSH: kunci saja, tanpa root, tanpa sandi"
cat >/etc/ssh/sshd_config.d/10-marantau.conf <<EOF
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowUsers $APP_USER
EOF
# Beberapa image cloud menaruh PasswordAuthentication yes di file lain; matikan juga.
for f in /etc/ssh/sshd_config.d/*.conf; do
  [ "$f" = /etc/ssh/sshd_config.d/10-marantau.conf ] && continue
  sed -i -E 's/^\s*(PasswordAuthentication|PermitRootLogin)\s+yes/# \0 (dimatikan marantau)/' "$f"
done
sshd -t
systemctl reload ssh

step "Firewall ufw: 22, 80, 443 saja"
ufw --force default deny incoming >/dev/null
ufw --force default allow outgoing >/dev/null
ufw limit 22/tcp >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw allow 443/udp >/dev/null
ufw --force enable >/dev/null
ufw status verbose | sed -n '1,20p'

step "fail2ban untuk SSH"
cat >/etc/fail2ban/jail.d/marantau.local <<'EOF'
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
systemctl enable --now fail2ban >/dev/null
systemctl restart fail2ban

step "Swap 2 GB (pengaman saja) + swappiness 10"
if ! swapon --show | grep -q /swapfile; then
  [ -f /swapfile ] || { fallocate -l 2G /swapfile; chmod 600 /swapfile; mkswap /swapfile >/dev/null; }
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
cat >/etc/sysctl.d/90-marantau.conf <<'EOF'
vm.swappiness=10
vm.overcommit_memory=1
net.core.somaxconn=1024
EOF
sysctl --system >/dev/null

step "Docker + Compose (repo resmi Docker)"
if ! command -v docker >/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
fi
mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
EOF
systemctl enable --now docker >/dev/null
systemctl restart docker
usermod -aG docker "$APP_USER"

# Catatan: Docker melewati ufw untuk port yang di-publish. Compose Marantau hanya
# mem-publish 80/443 (Caddy) dan 127.0.0.1:5432, jadi Postgres tetap tertutup.
step "Folder aplikasi"
install -d -o "$APP_USER" -g "$APP_USER" -m 750 /opt/marantau /opt/marantau/selfhost /opt/marantau/backup

step "Ringkasan"
echo "OS      : $(lsb_release -ds)"
echo "Docker  : $(docker --version)"
echo "Compose : $(docker compose version --short)"
echo "Swap    : $(swapon --show --noheadings | awk '{print $1, $3}')"
echo "RAM     : $(free -h | awk '/Mem:/{print $2" total, "$7" available"}')"
echo "Disk /  : $(df -h / | awk 'NR==2{print $4" sisa dari "$2}')"
echo "SSH     : $(sshd -T | grep -E '^(passwordauthentication|permitrootlogin) ' | tr '\n' ' ')"
echo "Port    : $(ss -tlnH | awk '{print $4}' | sort -u | tr '\n' ' ')"
echo
echo "SELESAI. Reboot tidak diperlukan sekarang."
