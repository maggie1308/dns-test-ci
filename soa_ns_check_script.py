import re
import subprocess
import json

# Функция для получения списка контейнеров с префиксом "dns-test-ci-"
def get_dns_test_containers():
    try:
        # Выполняем docker ps для получения списка всех запущенных контейнеров
        result = subprocess.check_output(["docker", "ps", "--format", "{{.Names}}"])
        container_names = result.decode().strip().split('\n')
        
        # Фильтруем контейнеры, которые начинаются с "dns-test-ci-"
        dns_test_containers = [name for name in container_names if name.startswith("dns-test-ci-")]
        return dns_test_containers
    except subprocess.CalledProcessError as e:
        print(f"Ошибка при получении списка контейнеров: {e}")
        return []

# Функция для получения IP-адреса контейнера
def get_container_ip(container_id):
    try:
        result = subprocess.check_output(["docker", "inspect", container_id])
        container_info = json.loads(result.decode())
        networks = container_info[0]["NetworkSettings"]["Networks"]
        if networks:
            for network_data in networks.values():
                return network_data["IPAddress"]
        return None
    except subprocess.CalledProcessError as e:
        print(f"Ошибка при получении IP-адреса контейнера {container_id}: {e}")
        return None

# Функция для получения конфигурации с контейнера
def get_container_config(container_id):
    try:
        # Чтение конфигурационного файла named.conf внутри контейнера
        result = subprocess.check_output(["docker", "exec", container_id, "cat", "/etc/bind/named.conf"])
        config = result.decode()
        return config
    except subprocess.CalledProcessError as e:
        print(f"Ошибка при получении конфигурации с {container_id}: {e}")
        return None
    
# Функция для выполнения DNS-запроса SOA
def get_soa(ip, zone):
    try:
        result = subprocess.check_output(["dig", f"@{ip}", zone, "SOA", "+short"])
        return result.decode().strip()
    except subprocess.CalledProcessError as e:
        print(f"Ошибка при выполнении запроса SOA для зоны {zone} на {ip}: {e}")
        return None

# Функция для выполнения DNS-запроса NS
def get_ns(ip, zone):
    try:
        result = subprocess.check_output(["dig", f"@{ip}", zone, "NS", "+short"])
        return result.decode().strip().split('\n')
    except subprocess.CalledProcessError as e:
        print(f"Ошибка при выполнении запроса NS для зоны {zone} на {ip}: {e}")
        return None

# Универсальная функция для поиска мастер-зон и IP-адресов для allow-transfer
def find_master_zones_with_ips(config_data):
    pattern = r'zone\s+"([\w\.]+)"(?:\s+IN)?\s*\{\s*[^}]*?type\s+master;\s*[^}]*?allow-transfer\s*\{([^}]+)\};'
    matches = re.findall(pattern, config_data, re.DOTALL)
    master_zones = []
    for match in matches:
        zone_name = match[0].strip()
        ip_addresses = [ip.strip() for ip in match[1].split(';') if ip.strip()]
        master_zones.append((zone_name, ip_addresses))
    return master_zones

# Основная функция для обработки контейнеров
def process_containers():
    # Получаем список контейнеров, которые начинаются с "dns-test-ci-"
    containers = get_dns_test_containers()
    
    if not containers:
        print("Не удалось найти контейнеры, начинающиеся с 'dns-test-ci-'")
        return

    for container_id in containers:
        print(f"Обработка конфигурации для контейнера: {container_id}")
        
        # Получаем IP-адрес контейнера
        master_ip = get_container_ip(container_id)
        if master_ip:
            print(f"IP-адрес контейнера: {master_ip}")
        else:
            print(f"Не удалось получить IP-адрес для контейнера {container_id}")
            continue
        
        # Получаем конфигурацию контейнера
        config_data = get_container_config(container_id)
        
        if config_data:
            # Парсим мастер-зоны
            master_zones = find_master_zones_with_ips(config_data)
            if master_zones:
                print(f"Найдены мастер-зоны для контейнера {container_id}:")
                for zone_name, slave_ips in master_zones:
                    print(f"- Зона: {zone_name}")
                    print(f"  Передается на IP-адреса: {slave_ips}")

                    # Проверяем SOA для master-контейнера
                    master_soa = get_soa(master_ip, zone_name)
                    if master_soa:
                        print(f"SOA запись для master {zone_name} на {master_ip}: {master_soa}")
                    else:
                        print(f"Не удалось получить SOA запись для master {zone_name} на {master_ip}")
                        continue

                    # Проверяем NS для master-контейнера
                    master_ns = get_ns(master_ip, zone_name)
                    if master_ns:
                        print(f"NS записи для master {zone_name} на {master_ip}: {master_ns}")
                    else:
                        print(f"Не удалось получить NS записи для master {zone_name} на {master_ip}")
                        continue

                    # Проверяем SOA и NS для slave-контейнеров и сверяем с master
                    for slave_ip in slave_ips:
                        slave_soa = get_soa(slave_ip, zone_name)
                        if slave_soa:
                            print(f"SOA запись для slave {zone_name} на {slave_ip}: {slave_soa}")
                            if master_soa == slave_soa:
                                print(f"SOA записи совпадают для {zone_name}")
                            else:
                                print(f"Ошибка: SOA записи не совпадают для {zone_name}")
                        else:
                            print(f"Не удалось получить SOA запись для slave {zone_name} на {slave_ip}")
                        
                        # Проверяем NS для slave-контейнеров
                        slave_ns = get_ns(slave_ip, zone_name)
                        if slave_ns:
                            print(f"NS записи для slave {zone_name} на {slave_ip}: {slave_ns}")
                            if set(master_ns) == set(slave_ns):
                                print(f"NS записи совпадают для {zone_name}")
                            else:
                                print(f"Ошибка: NS записи не совпадают для {zone_name}")
                        else:
                            print(f"Не удалось получить NS запись для slave {zone_name} на {slave_ip}")
            else:
                print(f"Мастер-зоны не найдены для контейнера {container_id}.")
        else:
            print(f"Не удалось прочитать конфигурацию контейнера {container_id}.")

# Запуск обработки контейнеров
process_containers()
