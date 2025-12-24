#!/bin/bash

# Скрипт для начальной настройки Ubuntu Server
# Практическая работа №1 - версия для Екатеринбурга

set -e  # Завершить скрипт при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функции для вывода
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка на выполнение от root
if [ "$EUID" -ne 0 ]; then
    print_error "Этот скрипт должен запускаться с правами root"
    exit 1
fi

print_info "=== Начало настройки Ubuntu Server ==="

# Шаг 1: Обновление системы
print_info "Шаг 1: Обновление пакетов системы..."
apt update && apt upgrade -y

# Установка необходимых утилит
print_info "Установка базовых утилит..."
apt install -y curl wget git htop nano vim ufw fail2ban logwatch unattended-upgrades net-tools

# Шаг 2: Настройка временной зоны (Екатеринбург)
print_info "Шаг 2: Настройка временной зоны (Екатеринбург)..."
timedatectl set-timezone Asia/Yekaterinburg
timedatectl set-ntp true

# Шаг 4: Настройка брандмауэра UFW
print_info "Шаг 4: Настройка брандмауэра UFW..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 2222/tcp comment 'SSH на кастомном порту'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw enable

# Шаг 5: Настройка Fail2Ban
print_info "Шаг 5: Настройка Fail2Ban..."

# Создание конфигурации jail.local
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = 2222
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[sshd-ddos]
enabled = true
port = 2222
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
EOF

systemctl enable fail2ban
systemctl start fail2ban

# Шаг 6: Настройка автоматических обновлений
print_info "Шаг 6: Настройка автоматических обновлений..."

cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Autoremove "1";
EOF

# Настройка автоматических обновлений безопасности
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

# Шаг 7: Настройка сети (Netplan) для подсети
print_info "Шаг 7: Настройка сети через Netplan для подсети"

# Поиск файла конфигурации netplan
NETPLAN_FILE=$(find /etc/netplan -name "*.yaml" -o -name "*.yml" | head -1)

if [ -z "$NETPLAN_FILE" ]; then
    NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
fi

# Резервное копирование
cp "$NETPLAN_FILE" "${NETPLAN_FILE}.backup"

# Показываем текущие сетевые интерфейсы
print_info "Текущие сетевые интерфейсы:"
ip link show | grep -E "^[0-9]+:" | awk -F: '{print $2}' | tr -d ' '

# Определяем основные сетевые интерфейсы
INTERFACES=($(ip link show | grep -E "^[0-9]+:" | awk -F: '{print $2}' | tr -d ' ' | grep -v lo))

if [ ${#INTERFACES[@]} -eq 0 ]; then
    print_error "Не найдены сетевые интерфейсы"
    exit 1
fi

MAIN_IFACE=${INTERFACES[0]}
SECOND_IFACE=""

if [ ${#INTERFACES[@]} -gt 1 ]; then
    SECOND_IFACE=${INTERFACES[1]}
fi

print_info "Основной интерфейс: $MAIN_IFACE"
if [ -n "$SECOND_IFACE" ]; then
    print_info "Второй интерфейс: $SECOND_IFACE"
fi

# Конфигурация для сети 172.16.10.0
# Первый интерфейс - DHCP или статический (по выбору)
read -p "Настроить $MAIN_IFACE как DHCP или статический? (dhcp/static) [dhcp]: " main_config
main_config=${main_config:-dhcp}

if [ "$main_config" = "static" ]; then
    read -p "Введите статический IP для $MAIN_IFACE (например 172.16.10.2/24): " main_ip
    read -p "Введите шлюз для $MAIN_IFACE: " main_gateway
    read -p "Введите DNS серверы (через запятую): " dns_servers
    dns_servers=${dns_servers:-8.8.8.8,8.8.4.4}
fi

# Создание конфигурации netplan
if [ -n "$SECOND_IFACE" ]; then
    # Конфигурация с двумя интерфейсами
    cat > "$NETPLAN_FILE" << EOF
network:
  version: 2
  ethernets:
    $MAIN_IFACE:
EOF
    
    if [ "$main_config" = "static" ]; then
        cat >> "$NETPLAN_FILE" << EOF
      dhcp4: no
      addresses: [$main_ip]
      routes:
        - to: default
          via: $main_gateway
      nameservers:
        addresses: [${dns_servers//,/,\ }]
EOF
    else
        cat >> "$NETPLAN_FILE" << EOF
      dhcp4: yes
EOF
    fi
    
    cat >> "$NETPLAN_FILE" << EOF
    $SECOND_IFACE:
      dhcp4: no
      addresses: [172.16.10.1/24]
EOF
else
    # Конфигурация с одним интерфейсом
    cat > "$NETPLAN_FILE" << EOF
network:
  version: 2
  ethernets:
    $MAIN_IFACE:
EOF
    
    if [ "$main_config" = "static" ]; then
        cat >> "$NETPLAN_FILE" << EOF
      dhcp4: no
      addresses: [$main_ip]
      routes:
        - to: default
          via: $main_gateway
      nameservers:
        addresses: [${dns_servers//,/,\ }]
EOF
    else
        cat >> "$NETPLAN_FILE" << EOF
      dhcp4: yes
EOF
    fi
fi

# Применение конфигурации сети
print_info "Применение конфигурации сети..."
netplan try --timeout 30
if [ $? -eq 0 ]; then
    netplan apply
    print_info "Конфигурация сети применена успешно"
else
    print_error "Ошибка в конфигурации сети. Возвращаем старую конфигурацию..."
    mv "${NETPLAN_FILE}.backup" "$NETPLAN_FILE"
    netplan apply
fi

# Шаг 8: Информация о системе
print_info "Шаг 8: Сбор информации о системе..."

# Установка hostname если еще не установлен
CURRENT_HOSTNAME=$(hostname)
if [ "$CURRENT_HOSTNAME" = "localhost" ] || [ "$CURRENT_HOSTNAME" = "ubuntu" ]; then
    read -p "Введите имя хоста (например server-ekb): " NEW_HOSTNAME
    if [ -n "$NEW_HOSTNAME" ]; then
        hostnamectl set-hostname "$NEW_HOSTNAME"
        sed -i "s/127.0.1.1.*$CURRENT_HOSTNAME/127.0.1.1\t$NEW_HOSTNAME/g" /etc/hosts
        print_info "Имя хоста изменено на: $NEW_HOSTNAME"
    fi
fi

echo "=== ИНФОРМАЦИЯ О СИСТЕМЕ ==="
lsb_release -a
echo ""
echo "Имя хоста: $(hostname)"
echo ""
echo "Версия ядра: $(uname -r)"
echo ""
echo "Сетевые интерфейсы:"
ip addr show
echo ""
echo "Маршрутизация:"
ip route show
echo ""
echo "Открытые порты:"
ss -tulpn | grep LISTEN

# Шаг 10: Дополнительные настройки для Екатеринбурга
print_info "Шаг 10: Дополнительные настройки..."

# Настройка локale
locale-gen ru_RU.UTF-8 en_US.UTF-8
update-locale LANG=ru_RU.UTF-8 LC_TIME=ru_RU.UTF-8

# Установка утилит для работы с сетью
apt install -y dnsutils traceroute mtr

print_info "=== НАСТРОЙКА ЗАВЕРШЕНА ==="
echo ""
echo "ИНФОРМАЦИЯ О СИСТЕМЕ:"
echo "1. Временная зона: Asia/Yekaterinburg"
echo "2. SSH порт: 2222"
echo "3. Пользователь: $CURRENT_USER"
echo "4. Сеть настроена в подсети 172.16.10.0"
if [ -n "$SECOND_IFACE" ]; then
    echo "5. Интерфейс $SECOND_IFACE имеет IP: 172.16.10.1/24"
fi
echo ""
echo "Для проверки системы используйте команду: system-check"
echo ""

# Проверка связи
print_info "Проверка сетевых настроек..."
ping -c 2 8.8.8.8 > /dev/null 2>&1
if [ $? -eq 0 ]; then
    print_info "Интернет соединение работает"
else
    print_warn "Нет интернет соединения. Проверьте настройки сети."
fi

print_info "Скрипт настройки завершен успешно!"
