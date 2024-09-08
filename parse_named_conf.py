import re
import subprocess
import json

# Функция для получения IP-адреса контейнера
def get_container_ip(container_id):
    try:
        # Выполняем docker inspect для получения информации о контейнере
        result = subprocess.check_output(["docker", "inspect", container_id])
        container_info = json.loads(result.decode())
        
        # Получаем IP из первого доступного сетевого интерфейса
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

# Универсальная функция для поиска мастер-зон и IP-адресов для allow-transfer
def find_master_zones_with_ips(config_data):
    # Универсальное регулярное выражение для парсинга зон с и без IN
    pattern = r'zone\s+"([\w\.]+)"(?:\s+IN)?\s*\{\s*[^}]*?type\s+master;\s*[^}]*?allow-transfer\s*\{([^}]+)\};'
    matches = re.findall(pattern, config_data, re.DOTALL)

    master_zones = []
    for match in matches:
        zone_name = match[0].strip()  # Название зоны
        ip_addresses = [ip.strip() for ip in match[1].split(';') if ip.strip()]  # Очистка IP-адресов и разбиение
        master_zones.append((zone_name, ip_addresses))

    return master_zones

# Основная функция для обработки контейнеров
def process_containers(containers):
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

                    # Проверяем SOA для slave-контейнеров и сверяем с master
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
            else:
                print(f"Мастер-зоны не найдены для контейнера {container_id}.")
        else:
            print(f"Не удалось прочитать конфигурацию контейнера {container_id}.")

# Пример списка контейнеров с префиксом "dns-test-ci-" (можно заменить на результат вызова docker ps)
containers = ["dns-test-ci-ns1.example.com-1", "dns-test-ci-ns2.example.com-1", "dns-test-ci-ns3.example.com-1"]

# Запуск обработки контейнеров
process_containers(containers)
