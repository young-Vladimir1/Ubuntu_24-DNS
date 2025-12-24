#!/bin/bash

# ============================================
# АВТОМАТИЧЕСКАЯ НАСТРОЙКА DNS КЛИЕНТА
# Для Ubuntu 24.04 / 22.04
# ============================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Настройки (измените под себя)
DNS_SERVER="172.16.10.1"     # IP DNS сервера
DOMAIN="vova.local"          # Домен
CLIENT_NAME="client1"        # Имя клиента
CLIENT_IP="172.16.10.201"    # IP клиента (опционально)

# Функции для вывода
print_success() { echo -e "${GREEN}[✓] $1${NC}"; }
print_error() { echo -e "${RED}[✗] $1${NC}"; }
print_info() { echo -e "${YELLOW}[i] $1${NC}"; }
print_step() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# Проверка прав
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Запустите скрипт с правами root: sudo $0"
        exit 1
    fi
}

# Шаг 1: Определение сетевого интерфейса
detect_interface() {
    print_step "1. Определение сетевого интерфейса"
    
    # Автоматически определяем активный интерфейс
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    
    if [ -z "$INTERFACE" ]; then
        INTERFACE=$(ip link | grep -E "^[0-9]+:" | grep "state UP" | awk -F': ' '{print $2}' | head -1)
    fi
    
    if [ -n "$INTERFACE" ]; then
        print_success "Найден интерфейс: $INTERFACE"
    else
        print_error "Не удалось определить сетевой интерфейс"
        exit 1
    fi
}

# Шаг 2: Установка имени хоста
setup_hostname() {
    print_step "2. Настройка имени хоста"
    
    # Текущее имя хоста
    CURRENT_HOSTNAME=$(hostname)
    print_info "Текущее имя хоста: $CURRENT_HOSTNAME"
    
    # Устанавливаем новое имя
    NEW_HOSTNAME="${CLIENT_NAME}.${DOMAIN}"
    hostnamectl set-hostname "$NEW_HOSTNAME"
    
    # Обновляем файл hostname
    echo "$NEW_HOSTNAME" > /etc/hostname
    
    print_success "Имя хоста установлено: $NEW_HOSTNAME"
}

# Шаг 3: Настройка файла hosts
setup_hosts() {
    print_step "3. Настройка файла hosts"
    
    # Создаем резервную копию
    cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d)
    
    # Получаем текущий IP (если не указан)
    if [ -z "$CLIENT_IP" ] || [ "$CLIENT_IP" = "авто" ]; then
        CLIENT_IP=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -1)
    fi
    
    # Создаем новый файл hosts
    cat > /etc/hosts << EOF
# Настройки hosts (сгенерировано автоматически)
127.0.0.1       localhost
127.0.1.1       ${CLIENT_NAME}.${DOMAIN} ${CLIENT_NAME}

# Локальная сеть
${DNS_SERVER}   server.${DOMAIN} server ns.${DOMAIN} dns.${DOMAIN} gateway.${DOMAIN}
${CLIENT_IP}    ${CLIENT_NAME}.${DOMAIN} ${CLIENT_NAME}

# Статические хосты (при необходимости добавьте свои)
172.16.10.10    www.${DOMAIN} web.${DOMAIN}
172.16.10.20    mail.${DOMAIN} smtp.${DOMAIN}
172.16.10.30    nas.${DOMAIN} files.${DOMAIN}

# IPv6
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF
    
    print_success "Файл hosts обновлен (резервная копия создана)"
    print_info "Ваш IP: $CLIENT_IP"
}

# Шаг 4: Настройка DNS через resolv.conf (временная)
setup_resolv_conf() {
    print_step "4. Временная настройка DNS"
    
    # Создаем резервную копию
    cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d)
    
    # Настраиваем DNS
    cat > /etc/resolv.conf << EOF
# DNS настройки (временные)
# Сгенерировано: $(date)
# Для постоянной настройки используйте Netplan

nameserver ${DNS_SERVER}
nameserver 8.8.8.8          # Google DNS (резервный)
nameserver 1.1.1.1          # Cloudflare (резервный)
search ${DOMAIN}
options timeout:2 attempts:3
EOF
    
    # Защищаем файл от перезаписи (опционально)
    chattr +i /etc/resolv.conf 2>/dev/null || true
    
    print_success "Временный DNS настроен"
    print_info "Основной DNS: $DNS_SERVER"
    print_info "Домен: $DOMAIN"
}

# Шаг 5: Настройка DNS через Netplan (постоянная)
setup_netplan() {
    print_step "5. Постоянная настройка DNS (Netplan)"
    
    # Проверяем наличие Netplan
    if [ -d /etc/netplan ]; then
        print_info "Найдена конфигурация Netplan"
        
        # Находим конфигурационный файл
        NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
        
        if [ -n "$NETPLAN_FILE" ]; then
            # Создаем резервную копию
            cp "$NETPLAN_FILE" "${NETPLAN_FILE}.backup.$(date +%Y%m%d)"
            
            # Парсим текущую конфигурацию
            CURRENT_YAML=$(cat "$NETPLAN_FILE")
            
            # Проверяем, есть ли уже настройки DNS
            if echo "$CURRENT_YAML" | grep -q "nameservers:"; then
                print_info "DNS уже настроен в Netplan, обновляю..."
                
                # Обновляем существующие настройки
                sed -i "/nameservers:/,/^[[:space:]]*[a-z]/ { /addresses:/ s/\[.*\]/\[${DNS_SERVER}, 8.8.8.8, 1.1.1.1\]/; /search:/ s/\[.*\]/\[${DOMAIN}\]/ }" "$NETPLAN_FILE"
            else
                print_info "Добавляю настройки DNS в Netplan..."
                
                # Добавляем настройки DNS
                # Это упрощенный вариант - для сложных конфигов может потребоваться ручная настройка
                echo "# ВНИМАНИЕ: Возможно потребуется ручная настройка DNS" > /tmp/netplan_warning.txt
                echo "# Добавьте в секцию интерфейса:" >> /tmp/netplan_warning.txt
                echo "#   nameservers:" >> /tmp/netplan_warning.txt
                echo "#     addresses: [${DNS_SERVER}, 8.8.8.8, 1.1.1.1]" >> /tmp/netplan_warning.txt
                echo "#     search: [${DOMAIN}]" >> /tmp/netplan_warning.txt
                
                cat /tmp/netplan_warning.txt
            fi
            
            # Применяем настройки
            print_info "Применяю настройки Netplan..."
            netplan apply 2>/dev/null && print_success "Netplan применен" || print_error "Ошибка применения Netplan"
            
        else
            print_info "Файл конфигурации Netplan не найден, создаю шаблон..."
            
            # Создаем простой конфиг
            cat > /etc/netplan/01-network-config.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: true
      dhcp6: false
      nameservers:
        addresses: [${DNS_SERVER}, 8.8.8.8, 1.1.1.1]
        search: [${DOMAIN}]
EOF
            
            netplan apply 2>/dev/null && print_success "Netplan создан и применен" || print_error "Ошибка создания Netplan"
        fi
    else
        print_info "Netplan не используется в этой системе"
    fi
}

# Шаг 6: Настройка systemd-resolved (альтернатива)
setup_systemd_resolved() {
    print_step "6. Настройка systemd-resolved"
    
    # Проверяем, используется ли systemd-resolved
    if systemctl is-active --quiet systemd-resolved; then
        print_info "Настраиваю systemd-resolved..."
        
        # Создаем резервную копию
        cp /etc/systemd/resolved.conf /etc/systemd/resolved.conf.backup.$(date +%Y%m%d) 2>/dev/null || true
        
        # Настраиваем
        cat > /etc/systemd/resolved.conf << EOF
[Resolve]
DNS=${DNS_SERVER} 8.8.8.8 1.1.1.1
Domains=${DOMAIN}
FallbackDNS=8.8.8.8 1.1.1.1
DNSOverTLS=no
DNSSEC=no
Cache=yes
DNSStubListener=yes
EOF
        
        # Перезапускаем службу
        systemctl restart systemd-resolved
        systemctl enable systemd-resolved
        
        # Создаем симлинк
        rm -f /etc/resolv.conf
        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
        
        print_success "systemd-resolved настроен"
    else
        print_info "systemd-resolved не активен, пропускаю"
    fi
}

# Шаг 7: Установка DNS утилит
install_utils() {
    print_step "7. Установка DNS утилит"
    
    print_info "Установка необходимых пакетов..."
    apt update > /dev/null 2>&1
    
    # Устанавливаем утилиты если их нет
    for pkg in dnsutils net-tools iputils-ping; do
        if ! dpkg -l | grep -q "^ii.*$pkg"; then
            apt install -y $pkg > /dev/null 2>&1 && \
            print_success "Установлен: $pkg" || \
            print_error "Ошибка установки: $pkg"
        fi
    done
}

# Шаг 8: Проверка связи с DNS сервером
check_connectivity() {
    print_step "8. Проверка связи"
    
    # Проверяем доступность DNS сервера
    print_info "Проверка связи с DNS сервером ($DNS_SERVER)..."
    
    if ping -c 2 -W 1 $DNS_SERVER > /dev/null 2>&1; then
        print_success "DNS сервер доступен"
        return 0
    else
        print_error "DNS сервер недоступен!"
        print_info "Проверьте:"
        print_info "1. Правильность IP адреса"
        print_info "2. Сетевую связность"
        print_info "3. Брандмауэр на сервере"
        return 1
    fi
}

# Шаг 9: Тестирование DNS
test_dns() {
    print_step "9. Тестирование DNS"
    
    echo -e "\n${YELLOW}Тест 1: Проверка локальных имен${NC}"
    
    local_success=0
    local_total=0
    
    for host in ns server www mail client1; do
        ((local_total++))
        full_host="${host}.${DOMAIN}"
        result=$(nslookup $full_host 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
        
        if [ -n "$result" ] && [ "$result" != "127.0.0.53" ]; then
            echo -e "${GREEN}✓${NC} $full_host -> $result"
            ((local_success++))
        else
            echo -e "${RED}✗${NC} $full_host -> не разрешается"
        fi
    done
    
    echo -e "\n${YELLOW}Тест 2: Проверка внешних сайтов${NC}"
    
    external_success=0
    external_total=0
    
    for site in google.com ya.ru github.com; do
        ((external_total++))
        result=$(nslookup $site 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
        
        if [ -n "$result" ]; then
            echo -e "${GREEN}✓${NC} $site -> $result"
            ((external_success++))
        else
            echo -e "${RED}✗${NC} $site -> не разрешается"
        fi
    done
    
    echo -e "\n${YELLOW}Тест 3: Проверка обратного разрешения${NC}"
    
    reverse_success=0
    reverse_total=0
    
    for ip in $DNS_SERVER $CLIENT_IP; do
        ((reverse_total++))
        result=$(nslookup $ip 2>/dev/null | grep "name =" | awk '{print $4}')
        
        if [ -n "$result" ]; then
            echo -e "${GREEN}✓${NC} $ip -> $result"
            ((reverse_success++))
        else
            echo -e "${RED}✗${NC} $ip -> не разрешается"
        fi
    done
    
    # Сводка
    echo -e "\n${BLUE}=== РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ ===${NC}"
    echo "Локальные имена: $local_success/$local_total"
    echo "Внешние сайты: $external_success/$external_total"
    echo "Обратное разрешение: $reverse_success/$reverse_total"
    
    if [ $local_success -eq $local_total ] && [ $external_success -gt 0 ]; then
        print_success "DNS работает корректно!"
    else
        print_error "Есть проблемы с DNS!"
    fi
}

# Шаг 10: Создание скрипта диагностики
create_diagnostic_script() {
    print_step "10. Создание скрипта диагностики"
    
    cat > /usr/local/bin/check-dns << 'EOF'
#!/bin/bash

# Скрипт диагностики DNS
echo "=== ДИАГНОСТИКА DNS ==="
echo ""

echo "1. Информация о системе:"
echo "   Имя хоста: $(hostname)"
echo "   Домен: $(domainname 2>/dev/null || echo 'не установлен')"
echo ""

echo "2. Сетевые интерфейсы:"
ip addr show | grep -E "inet |^[0-9]+:" | head -10
echo ""

echo "3. Настройки DNS:"
echo "   /etc/resolv.conf:"
cat /etc/resolv.conf 2>/dev/null | sed 's/^/     /'
echo ""

echo "4. Маршрут по умолчанию:"
ip route | grep default
echo ""

echo "5. Проверка связи с DNS сервером:"
DNS_SERVER=$(grep nameserver /etc/resolv.conf 2>/dev/null | head -1 | awk '{print $2}')
if [ -n "$DNS_SERVER" ]; then
    echo "   DNS сервер: $DNS_SERVER"
    ping -c 2 -W 1 $DNS_SERVER > /dev/null 2>&1 && \
        echo "   Статус: ✓ доступен" || \
        echo "   Статус: ✗ недоступен"
else
    echo "   DNS сервер: не настроен"
fi
echo ""

echo "6. Тест разрешения имен:"
for host in localhost $(hostname) google.com; do
    result=$(timeout 2 nslookup $host 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}')
    if [ -n "$result" ]; then
        echo "   ✓ $host -> $result"
    else
        echo "   ✗ $host -> не разрешается"
    fi
done
echo ""

echo "7. Используемые службы DNS:"
systemctl is-active systemd-resolved >/dev/null 2>&1 && echo "   systemd-resolved: активен" || echo "   systemd-resolved: не активен"
systemctl is-active NetworkManager >/dev/null 2>&1 && echo "   NetworkManager: активен" || echo "   NetworkManager: не активен"
echo ""

echo "8. Порт 53 (если слушается):"
netstat -tulpn | grep :53 | head -5
echo ""

echo "=== КОНЕЦ ДИАГНОСТИКИ ==="
EOF
    
    chmod +x /usr/local/bin/check-dns
    print_success "Скрипт диагностики создан: check-dns"
}

# Шаг 11: Информация для пользователя
show_info() {
    print_step "11. ИНФОРМАЦИЯ ДЛЯ ПОЛЬЗОВАТЕЛЯ"
    
    cat << EOF

${GREEN}НАСТРОЙКА ЗАВЕРШЕНА!${NC}

${YELLOW}Ваши настройки:${NC}
• Имя компьютера: ${CLIENT_NAME}.${DOMAIN}
• DNS сервер: ${DNS_SERVER}
• Домен: ${DOMAIN}
• Сетевой интерфейс: ${INTERFACE}
• Ваш IP: ${CLIENT_IP}

${YELLOW}Доступные команды:${NC}
• Проверить DNS: ${GREEN}check-dns${NC}
• Проверить связь: ${GREEN}ping ${DNS_SERVER}${NC}
• Тест DNS: ${GREEN}nslookup server.${DOMAIN}${NC}
• Ваше имя: ${GREEN}hostname${NC}

${YELLOW}Доступные хосты в сети:${NC}
• server.${DOMAIN} - DNS сервер (${DNS_SERVER})
• ns.${DOMAIN} - то же что server
• www.${DOMAIN} - веб сервер (172.16.10.10)
• mail.${DOMAIN} - почтовый сервер (172.16.10.20)
• ${CLIENT_NAME}.${DOMAIN} - этот компьютер (${CLIENT_IP})

${YELLOW}Если что-то не работает:${NC}
1. Проверьте связь: ${GREEN}ping ${DNS_SERVER}${NC}
2. Запустите диагностику: ${GREEN}check-dns${NC}
3. Проверьте настройки: ${GREEN}cat /etc/resolv.conf${NC}
4. Перезагрузите сеть: ${GREEN}sudo systemctl restart systemd-networkd${NC}

${RED}ВАЖНО:${NC}
• Резервные копии созданы в:
  /etc/hosts.backup.*
  /etc/resolv.conf.backup.*
  /etc/netplan/*.backup.*
  
• Для сброса настроек удалите /etc/resolv.conf и восстановите из backup
EOF
}

# ============================================
# ОСНОВНОЙ ПРОЦЕСС
# ============================================

print_info "НАСТРОЙКА DNS КЛИЕНТА"
print_info "DNS сервер: $DNS_SERVER"
print_info "Домен: $DOMAIN"
print_info "Имя клиента: $CLIENT_NAME"

# Запрос подтверждения
read -p "Продолжить настройку? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Отменено пользователем"
    exit 0
fi

check_root

# Выполняем шаги
detect_interface
setup_hostname
setup_hosts
install_utils
check_connectivity || {
    print_error "Нет связи с DNS сервером. Продолжаю настройку, но возможны проблемы."
    read -p "Продолжить? (y/N): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
}

setup_resolv_conf
setup_netplan
setup_systemd_resolved
create_diagnostic_script
test_dns
show_info

print_step "НАСТРОЙКА ЗАВЕРШЕНА!"
print_success "Клиент настроен для работы с DNS сервером $DNS_SERVER"
print_info "Используйте команду 'check-dns' для диагностики"
