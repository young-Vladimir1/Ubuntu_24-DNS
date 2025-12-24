#!/bin/bash

# ============================================
# АВТОМАТИЧЕСКАЯ НАСТРОЙКА DNS СЕРВЕРА
# Для Ubuntu 24.04 / 22.04
# ============================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ваши данные (измените под себя)
DOMAIN="vova.local"
SERVER_IP="172.16.10.1"
CLIENT_IP="172.16.10.201"
NETWORK="172.16.10.0/24"
EXTERNAL_IP="172.16.10.101"

# Функции для вывода
print_success() { echo -e "${GREEN}[✓] $1${NC}"; }
print_error() { echo -e "${RED}[✗] $1${NC}"; }
print_info() { echo -e "${YELLOW}[i] $1${NC}"; }
print_step() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

# Проверка прав root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Запустите скрипт с правами root: sudo $0"
        exit 1
    fi
}

# Шаг 1: Установка BIND9
install_bind9() {
    print_step "1. Установка BIND9"
    
    print_info "Обновление пакетов..."
    apt update > /dev/null 2>&1
    
    print_info "Установка BIND9 и утилит..."
    apt install -y bind9 bind9utils dnsutils net-tools > /dev/null 2>&1
    
    if systemctl is-active --quiet bind9; then
        print_success "BIND9 установлен и запущен"
    else
        print_error "Ошибка установки BIND9"
        exit 1
    fi
}

# Шаг 2: Создание конфигурационных файлов
create_configs() {
    print_step "2. Создание конфигурационных файлов"
    
    # Создаем директорию для бэкапа
    mkdir -p /etc/bind/backup
    cp -r /etc/bind/* /etc/bind/backup/ 2>/dev/null
    
    # 2.1 Основной конфиг
    cat > /etc/bind/named.conf << EOF
// Основные настройки DNS сервера
options {
    directory "/var/cache/bind";
    
    // Разрешить запросы отовсюду
    allow-query { any; };
    
    // Разрешить рекурсию
    recursion yes;
    
    // Внешние DNS-серверы
    forwarders {
        8.8.8.8;        // Google DNS
        8.8.4.4;        // Google DNS
        1.1.1.1;        // Cloudflare
    };
    
    // Слушать на всех интерфейсах
    listen-on { any; };
    listen-on-v6 { any; };
    
    // Отключить DNSSEC для простоты
    dnssec-validation no;
    
    // Разрешить рекурсию для локальной сети
    allow-recursion { 
        ${NETWORK};  // Ваша сеть
        127.0.0.0/8;     // localhost
        192.168.0.0/16;  // Домашние сети
    };
};

// Прямая зона для домена
zone "${DOMAIN}" {
    type master;
    file "/etc/bind/db.${DOMAIN}";
};

// Обратная зона для вашей сети
zone "10.16.172.in-addr.arpa" {
    type master;
    file "/etc/bind/db.172.16.10";
};

// Подключаем стандартные зоны
include "/etc/bind/named.conf.default-zones";
EOF
    print_success "Создан /etc/bind/named.conf"
    
    # 2.2 Прямая зона
    cat > /etc/bind/db.${DOMAIN} << EOF
\$TTL 86400
@   IN  SOA ns.${DOMAIN}. admin.${DOMAIN}. (
    $(date +%Y%m%d)01  ; Serial
    3600        ; Refresh
    1800        ; Retry
    604800      ; Expire
    86400       ; Minimum TTL
)

; DNS-серверы
@       IN  NS  ns.${DOMAIN}.

; Основные записи
@               IN  A   ${SERVER_IP}
ns              IN  A   ${SERVER_IP}
server          IN  A   ${SERVER_IP}
dns             IN  A   ${SERVER_IP}
dhcp            IN  A   ${SERVER_IP}
gateway         IN  A   ${SERVER_IP}

; Клиенты
client1         IN  A   ${CLIENT_IP}
pc1             IN  A   ${CLIENT_IP}
workstation     IN  A   ${CLIENT_IP}

; Сервисы
www             IN  A   172.16.10.10
web             IN  A   172.16.10.10
mail            IN  A   172.16.10.20
smtp            IN  A   172.16.10.20
nas             IN  A   172.16.10.30
files           IN  A   172.16.10.30

; Внешний адрес сервера
server-ext      IN  A   ${EXTERNAL_IP}
external        IN  A   ${EXTERNAL_IP}

; Псевдонимы
router          IN  CNAME   gateway
imap            IN  CNAME   mail
pop3            IN  CNAME   mail
ftp             IN  CNAME   nas
test            IN  CNAME   www
EOF
    print_success "Создан /etc/bind/db.${DOMAIN}"
    
    # 2.3 Обратная зона
    cat > /etc/bind/db.172.16.10 << EOF
\$TTL 86400
@   IN  SOA ns.${DOMAIN}. admin.${DOMAIN}. (
    $(date +%Y%m%d)01  ; Serial
    3600        ; Refresh
    1800        ; Retry
    604800      ; Expire
    86400       ; Minimum TTL
)

@       IN  NS  ns.${DOMAIN}.

; Обратные записи для сети 172.16.10.0/24
1       IN  PTR ns.${DOMAIN}.
1       IN  PTR server.${DOMAIN}.
1       IN  PTR dns.${DOMAIN}.
1       IN  PTR dhcp.${DOMAIN}.
1       IN  PTR gateway.${DOMAIN}.

101     IN  PTR server-ext.${DOMAIN}.
101     IN  PTR external.${DOMAIN}.

201     IN  PTR client1.${DOMAIN}.
201     IN  PTR pc1.${DOMAIN}.
201     IN  PTR workstation.${DOMAIN}.

10      IN  PTR www.${DOMAIN}.
10      IN  PTR web.${DOMAIN}.
20      IN  PTR mail.${DOMAIN}.
20      IN  PTR smtp.${DOMAIN}.
30      IN  PTR nas.${DOMAIN}.
30      IN  PTR files.${DOMAIN}.
EOF
    print_success "Создан /etc/bind/db.172.16.10"
}

# Шаг 3: Проверка конфигурации
check_configs() {
    print_step "3. Проверка конфигурации"
    
    print_info "Проверка основного конфига..."
    if named-checkconf > /dev/null 2>&1; then
        print_success "Конфигурация синтаксически верна"
    else
        print_error "Ошибка в конфигурации"
        named-checkconf
        exit 1
    fi
    
    print_info "Проверка прямой зоны..."
    if named-checkzone ${DOMAIN} /etc/bind/db.${DOMAIN} > /dev/null 2>&1; then
        print_success "Прямая зона корректна"
    else
        print_error "Ошибка в прямой зоне"
        named-checkzone ${DOMAIN} /etc/bind/db.${DOMAIN}
        exit 1
    fi
    
    print_info "Проверка обратной зоны..."
    if named-checkzone 10.16.172.in-addr.arpa /etc/bind/db.172.16.10 > /dev/null 2>&1; then
        print_success "Обратная зона корректна"
    else
        print_error "Ошибка в обратной зоне"
        named-checkzone 10.16.172.in-addr.arpa /etc/bind/db.172.16.10
        exit 1
    fi
}

# Шаг 4: Настройка брандмауэра
setup_firewall() {
    print_step "4. Настройка брандмауэра"
    
    # Проверяем установлен ли ufw
    if command -v ufw > /dev/null 2>&1; then
        print_info "Настройка UFW..."
        ufw allow 53/tcp > /dev/null 2>&1
        ufw allow 53/udp > /dev/null 2>&1
        ufw reload > /dev/null 2>&1
        print_success "Правила брандмауэра добавлены"
    else
        print_info "UFW не установлен, пропускаем"
    fi
}

# Шаг 5: Запуск и настройка службы
start_service() {
    print_step "5. Запуск DNS сервера"
    
    print_info "Перезапуск BIND9..."
    systemctl restart bind9 > /dev/null 2>&1
    
    if systemctl is-active --quiet bind9; then
        print_success "BIND9 успешно запущен"
    else
        print_error "Не удалось запустить BIND9"
        journalctl -u bind9 -n 10 --no-pager
        exit 1
    fi
    
    print_info "Включение автозагрузки..."
    systemctl enable bind9 > /dev/null 2>&1
    print_success "BIND9 настроен на автозагрузку"
}

# Шаг 6: Настройка локального DNS
setup_local_dns() {
    print_step "6. Настройка локального DNS"
    
    # Создаем резервную копию
    cp /etc/resolv.conf /etc/resolv.conf.backup
    
    # Настраиваем локальный DNS
    cat > /etc/resolv.conf << EOF
# Настройки DNS (автоматически сгенерированы)
nameserver 127.0.0.1
nameserver 8.8.8.8
nameserver 1.1.1.1
search ${DOMAIN}
EOF
    
    print_success "Локальный DNS настроен (резервная копия: /etc/resolv.conf.backup)"
}

# Шаг 7: Тестирование
test_dns() {
    print_step "7. Тестирование DNS сервера"
    
    echo -e "\n${YELLOW}Тест 1: Проверка службы${NC}"
    systemctl status bind9 --no-pager | grep -A5 "Active:"
    
    echo -e "\n${YELLOW}Тест 2: Проверка портов${NC}"
    netstat -tulpn | grep :53 || echo "Порт 53 не слушается"
    
    echo -e "\n${YELLOW}Тест 3: Локальные запросы${NC}"
    for host in ns server client1 www; do
        result=$(dig @127.0.0.1 ${host}.${DOMAIN} +short 2>/dev/null | head -1)
        if [ -n "$result" ]; then
            echo -e "${GREEN}✓${NC} ${host}.${DOMAIN} -> $result"
        else
            echo -e "${RED}✗${NC} ${host}.${DOMAIN} -> не разрешается"
        fi
    done
    
    echo -e "\n${YELLOW}Тест 4: Обратные запросы${NC}"
    for ip in ${SERVER_IP} ${CLIENT_IP} ${EXTERNAL_IP}; do
        result=$(dig @127.0.0.1 -x $ip +short 2>/dev/null | head -1)
        if [ -n "$result" ]; then
            echo -e "${GREEN}✓${NC} $ip -> $result"
        else
            echo -e "${RED}✗${NC} $ip -> не разрешается"
        fi
    done
    
    echo -e "\n${YELLOW}Тест 5: Внешние запросы${NC}"
    for site in google.com ya.ru github.com; do
        result=$(dig @127.0.0.1 $site +short 2>/dev/null | head -1)
        if [ -n "$result" ]; then
            echo -e "${GREEN}✓${NC} $site -> $result"
        else
            echo -e "${RED}✗${NC} $site -> не разрешается"
        fi
    done
}

# Шаг 8: Инструкция для клиента
client_instructions() {
    print_step "8. Инструкция для клиентов"
    
    cat << EOF

${GREEN}НАСТРОЙКА КЛИЕНТОВ:${NC}

1. На клиентской машине откройте терминал

2. Настройте DNS (временная настройка):
   ${YELLOW}sudo nano /etc/resolv.conf${NC}
   Добавьте:
   nameserver ${SERVER_IP}
   search ${DOMAIN}

3. Для постоянной настройки (Ubuntu 22.04+):
   ${YELLOW}sudo nano /etc/netplan/00-installer-config.yaml${NC}
   Добавьте в секцию интерфейса:
   nameservers:
     addresses: [${SERVER_IP}]
     search: [${DOMAIN}]
   Затем: ${YELLOW}sudo netplan apply${NC}

4. Тестирование с клиента:
   ${YELLOW}nslookup server.${DOMAIN}${NC}
   ${YELLOW}nslookup client1.${DOMAIN}${NC}
   ${YELLOW}nslookup google.com${NC}

${GREEN}ДОСТУПНЫЕ ХОСТЫ:${NC}
• server.${DOMAIN} / ns.${DOMAIN} - DNS сервер (${SERVER_IP})
• client1.${DOMAIN} - клиент (${CLIENT_IP})
• www.${DOMAIN} / web.${DOMAIN} - веб сервер (172.16.10.10)
• mail.${DOMAIN} - почтовый сервер (172.16.10.20)
• router.${DOMAIN} - шлюз (псевдоним)

${GREEN}КОМАНДЫ УПРАВЛЕНИЯ:${NC}
• Перезагрузка конфигурации: ${YELLOW}sudo rndc reload${NC}
• Очистка кэша: ${YELLOW}sudo rndc flush${NC}
• Статистика: ${YELLOW}sudo rndc stats${NC}
• Просмотр логов: ${YELLOW}sudo journalctl -u bind9 -f${NC}
EOF
}

# Шаг 9: Создание скрипта управления
create_control_script() {
    print_step "9. Создание скрипта управления"
    
    cat > /usr/local/bin/dns-control << 'EOF'
#!/bin/bash

case "$1" in
    start)
        systemctl start bind9
        echo "DNS сервер запущен"
        ;;
    stop)
        systemctl stop bind9
        echo "DNS сервер остановлен"
        ;;
    restart)
        systemctl restart bind9
        echo "DNS сервер перезапущен"
        ;;
    status)
        systemctl status bind9 --no-pager
        ;;
    reload)
        rndc reload
        echo "Конфигурация перезагружена"
        ;;
    flush)
        rndc flush
        echo "Кэш DNS очищен"
        ;;
    test)
        echo "Тестирование DNS:"
        dig @127.0.0.1 ns.vova.local +short
        dig @127.0.0.1 google.com +short
        ;;
    add)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Использование: dns-control add <имя> <IP>"
            exit 1
        fi
        echo "$2 IN A $3" >> /etc/bind/db.vova.local
        echo "$(echo $3 | cut -d. -f4) IN PTR $2.vova.local." >> /etc/bind/db.172.16.10
        rndc reload
        echo "Запись $2.vova.local -> $3 добавлена"
        ;;
    logs)
        journalctl -u bind9 -n 30 --no-pager
        ;;
    *)
        echo "Использование: dns-control {start|stop|restart|status|reload|flush|test|add|logs}"
        echo "  start    - запустить DNS сервер"
        echo "  stop     - остановить DNS сервер"
        echo "  restart  - перезапустить DNS сервер"
        echo "  status   - статус службы"
        echo "  reload   - перезагрузить конфигурацию"
        echo "  flush    - очистить кэш DNS"
        echo "  test     - проверить работу"
        echo "  add <имя> <IP> - добавить новую запись"
        echo "  logs     - показать логи"
        exit 1
        ;;
esac
EOF
    
    chmod +x /usr/local/bin/dns-control
    print_success "Скрипт управления создан: dns-control"
}

# ============================================
# ОСНОВНОЙ ПРОЦЕСС
# ============================================

print_info "НАСТРОЙКА DNS СЕРВЕРА"
print_info "Домен: ${DOMAIN}"
print_info "Сервер: ${SERVER_IP}"
print_info "Клиент: ${CLIENT_IP}"
print_info "Сеть: ${NETWORK}"

check_root

# Выполняем все шаги
install_bind9
create_configs
check_configs
setup_firewall
start_service
setup_local_dns
create_control_script
test_dns
client_instructions

print_step "НАСТРОЙКА ЗАВЕРШЕНА!"
print_success "DNS сервер готов к работе!"
print_info "Используйте команду 'dns-control' для управления"
