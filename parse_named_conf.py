import re
import subprocess

# Функция для получения конфигурации с контейнера
def get_container_config(container_id):
    try:
        # Чтение конфигурационного файла named.conf внутри контейнера
        result = subprocess.check_output(["docker", "exec", container_id, "cat", "/etc/bind/named.conf"])
        config = result.decode()
        # print(config)  Для отладки можно вывести конфигурацию
        return config
    except subprocess.CalledProcessError as e:
        print(f"Ошибка при получении конфигурации с {container_id}: {e}")
        return None

# Функция для поиска мастер-зон и IP-адресов для allow-transfer
def find_master_zones_with_ips(config_data):
    # Ищем зоны, где первая строка начинается с zone, а вторая с type master
    pattern = r'zone\s+"(.*?)"\s*\{[^\}]*?type\s+master;.*?allow-transfer\s*\{(.*?)\};'
    matches = re.findall(pattern, config_data, re.DOTALL)
    
    master_zones = []
    for match in matches:
        zone_name = match[0].strip()  # Название зоны
        if zone_name == ".":  # Игнорируем зону "."
            continue

        ip_addresses = match[1].replace(';', '').split()  # Удаляем ";" и разбиваем строку
        master_zones.append((zone_name, ip_addresses))

    return master_zones

# Основная функция для обработки контейнеров
def process_containers(containers):
    for container_id in containers:
        print(f"Обработка конфигурации для контейнера: {container_id}")
        config_data = get_container_config(container_id)
        
        if config_data:
            master_zones = find_master_zones_with_ips(config_data)
            if master_zones:
                print(f"Найдены мастер-зоны для контейнера {container_id}:")
                for zone_name, ip_addresses in master_zones:
                    print(f"- Зона: {zone_name}")
                    print(f"  Передается на IP-адреса: {ip_addresses}")
            else:
                print(f"Мастер-зоны не найдены для контейнера {container_id}.")
        else:
            print(f"Не удалось прочитать конфигурацию контейнера {container_id}.")

# Пример списка контейнеров с префиксом "dns-test-ci-" (можно заменить на результат вызова docker ps)
containers = ["dns-test-ci-ns1.example.com-1", "dns-test-ci-ns2.example.com-1", "dns-test-ci-ns3.example.com-1"]

# Запуск обработки контейнеров
process_containers(containers)
