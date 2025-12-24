#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_success() { echo -e "${GREEN}[✓] $1${NC}"; }
echo_error() { echo -e "${RED}[✗] $1${NC}"; }
echo_info() { echo -e "${YELLOW}[i] $1${NC}"; }

echo_info "НАСТРОЙКА SSH СЕРВЕРА"

# 1. Установка SSH
echo_info "1. Установка OpenSSH Server..."
sudo apt update > /dev/null 2>&1
sudo apt install -y openssh-server > /dev/null 2>&1
echo_success "SSH сервер установлен"

# 2. Настройка конфигурации
echo_info "2. Настройка конфигурации..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Простая безопасная конфигурация
sudo tee /etc/ssh/sshd_config << 'EOF' > /dev/null
# Основные настройки
Port 22
Protocol 2
ListenAddress 0.0.0.0

# Безопасность
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication yes
ChallengeResponseAuthentication no

# Настройки пользователей
AllowUsers student vova
UsePAM yes
X11Forwarding yes
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes

# Лимиты
MaxAuthTries 3
MaxSessions 10
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

echo_success "Конфигурация обновлена"

# 3. Создание пользователя
echo_info "3. Создание пользователя student..."
if id "student" &>/dev/null; then
    echo_info "Пользователь student уже существует"
else
    sudo useradd -m -s /bin/bash student
    echo "student:student123" | sudo chpasswd
    echo_success "Пользователь student создан (пароль: student123)"
fi

# 4. Запуск службы
echo_info "4. Запуск SSH службы..."
sudo systemctl restart ssh
sudo systemctl enable ssh > /dev/null 2>&1

# 5. Проверка
echo_info "5. Проверка работы..."
if sudo systemctl is-active --quiet ssh; then
    echo_success "SSH сервер запущен"
    
    IP_ADDR=$(ip addr show ens37 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    if [ -z "$IP_ADDR" ]; then
        IP_ADDR=$(hostname -I | awk '{print $1}')
    fi
    
    echo ""
    echo_success "✅ SSH сервер настроен!"
    echo_info "IP адрес: $IP_ADDR"
    echo_info "Порт: 22"
    echo_info "Пользователи: student, vova"
    echo_info "Пароль student: student123"
else
    echo_error "Ошибка запуска SSH сервера"
    sudo journalctl -u ssh -n 5 --no-pager
fi

echo ""
echo_info "КОМАНДЫ ДЛЯ ПОДКЛЮЧЕНИЯ С КЛИЕНТА:"
echo "  ssh student@172.16.10.1"
echo "  ssh vova@172.16.10.1"
