#!/bin/bash

# Скрипт настройки SSH клиента
# Для клиента, который подключается к 172.16.10.1

echo "=== НАСТРОЙКА SSH КЛИЕНТА ==="

# 1. Установка SSH клиента
echo "1. Установка SSH клиента..."
sudo apt update
sudo apt install -y openssh-client

# 2. Создание пользователя (если нужно)
echo "2. Проверка пользователя..."
read -p "Создать пользователя student на клиенте? (y/n): " create_user
if [[ $create_user == "y" || $create_user == "Y" ]]; then
    if ! id "student" &>/dev/null; then
        sudo useradd -m -s /bin/bash student
        echo "student:student123" | sudo chpasswd
        echo "Пользователь student создан (пароль: student123)"
    else
        echo "Пользователь student уже существует"
    fi
fi

# 3. Проверка подключения
echo "3. Проверка подключения к серверу..."
SERVER_IP="172.16.10.1"

# Проверка ping
echo -n "Проверка связи с сервером $SERVER_IP... "
if ping -c 1 -W 1 $SERVER_IP &> /dev/null; then
    echo "OK"
else
    echo "НЕТ СВЯЗИ"
    echo "Проверьте сетевые настройки"
    exit 1
fi

# Проверка порта SSH
echo -n "Проверка порта SSH (22)... "
if timeout 2 bash -c "cat < /dev/null > /dev/tcp/$SERVER_IP/22" 2>/dev/null; then
    echo "ОТКРЫТ"
else
    echo "ЗАКРЫТ"
    echo "На сервере может не работать SSH"
fi

# 4. Инструкция по подключению
echo ""
echo "=== ИНСТРУКЦИЯ ==="
echo ""
echo "Для подключения к серверу выполните:"
echo "ssh student@172.16.10.1"
echo ""
echo "Пароль: student123"
echo ""
echo "Если нужно выйти из SSH сессии, введите: exit"
echo ""
echo "Тестовое подключение:"
echo "ssh -o ConnectTimeout=5 student@172.16.10.1 'echo Успешное подключение!'"
