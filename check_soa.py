import re
import subprocess
import json
import sys  # Для получения аргументов командной строки

# Префикс для контейнеров
CONTAINER_PREFIX = "dns-test-ci-"

# Функция для получения списка контейнеров с префиксом и их названий машин
def get_dns_test_containers(machine_names):
    try:
        # Выполняем docker ps для получения списка всех запущенных контейнеров
        result = subprocess.check_output(["docker", "ps", "--format", "{{.Names}}"])
        container_names = result.decode().strip().split('\n')
        print(result)
        print(container_names)
        # Преобразуем имена машин в имена контейнеров с префиксом
        containers_to_check = [ CONTAINER_PREFIX + name + "-1" for name in machine_names]
        print("Преобразуем имена машин в имена контейнеров с префиксом")
        print(containers_to_check)
        # Фильтруем контейнеры, которые присутствуют среди запущенных контейнеров
        dns_test_containers = [name for name in container_names if name in containers_to_check]
        print("Фильтруем контейнеры, которые присутствуют среди запущенных контейнеров")
        print(dns_test_containers)
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

# Основная функция для обработки контейнеров и создания массива со словарями
def process_containers(machine_names):
    # Преобразуем имена машин в имена контейнеров и фильтруем запущенные контейнеры
    dns_test_containers = get_dns_test_containers(machine_names)
    print(dns_test_containers)
    if not dns_test_containers:
        print("Не удалось найти контейнеры, чьи конфигурации изменились")
        return []

    result_list = []  # Список для хранения результата
    
    for container_id in dns_test_containers:
        print(f"Обработка конфигурации для контейнера: {container_id}")
        
        # Получаем IP-адрес контейнера
        master_ip = get_container_ip(container_id)
        if not master_ip:
            print(f"Не удалось получить IP-адрес для контейнера {container_id}")
            continue
        
        # Получаем конфигурацию контейнера
        config_data = get_container_config(container_id)
        if not config_data:
            print(f"Не удалось прочитать конфигурацию контейнера {container_id}")
            continue
        
        # Парсим мастер-зоны и создаем словарь для текущего контейнера
        master_zones = find_master_zones_with_ips(config_data)
        if master_zones:
            zone_dict = {}  # Словарь для хранения зон и SOA
            for zone_name, _ in master_zones:
                master_soa = get_soa(master_ip, zone_name)
                if master_soa:
                    zone_dict[zone_name] = master_soa  # Добавляем зону и её SOA в словарь
                else:
                    print(f"Не удалось получить SOA для зоны {zone_name} на {master_ip}")

            if zone_dict:
                # Добавляем в результат IP-адрес и словарь с зонами и их SOA
                result_list.append({master_ip: zone_dict})

    return result_list

# Получаем изменённые машины из аргументов командной строки
changed_machines = sys.argv[1:]

# Запуск обработки контейнеров
soa_data = process_containers(changed_machines)

# Сохранение результата в файл JSON
with open('soa_results.json', 'w') as f:
    json.dump(soa_data, f)

# Вывод для Bash-скрипта
print(json.dumps(soa_data))
