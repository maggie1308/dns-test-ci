import subprocess
import sys
import re

# Получение списка контейнеров с префиксом dns-test-ci-
def get_containers():
    try:
        result = subprocess.check_output(["docker", "ps", "--filter", "name=dns-test-ci-", "--format", "{{.Names}}"])
        containers = result.decode().strip().split('\n')
        return containers if containers else []
    except subprocess.CalledProcessError as e:
        print(f"Ошибка при получении списка контейнеров: {e}")
        sys.exit(1)

# Проверка SOA для мастер контейнеров
def check_soa(container_id, zone):
    try:
        result = subprocess.check_output(["docker", "exec", container_id, "dig", "@localhost", "SOA", zone])
        output = result.decode()
        print(f"SOA-запрос для {container_id} успешно выполнен для зоны {zone}")
        return output
    except subprocess.CalledProcessError:
        print(f"Ошибка: {container_id} не отвечает на SOA-запросы для зоны {zone}")
        sys.exit(1)

# Проверка NS для мастер контейнеров
def check_ns(container_id, zone):
    try:
        result = subprocess.check_output(["docker", "exec", container_id, "dig", "@localhost", "NS", zone])
        output = result.decode()
        print(f"NS-запрос для {container_id} успешно выполнен для зоны {zone}")
        return output
    except subprocess.CalledProcessError:
        print(f"Ошибка: {container_id} не отвечает на NS-запросы для зоны {zone}")
        sys.exit(1)

# Извлечение зон из конфигурации named.conf
def get_zones_from_config(container_id):
    try:
        result = subprocess.check_output(["docker", "exec", container_id, "cat", "/etc/bind/named.conf"])
        config = result.decode()
        zones = re.findall(r'zone\s+"(.*?)"', config)
        zone_types = re.findall(r'type\s+(master|slave);', config)
        zone_data = dict(zip(zones, zone_types))
        return zone_data
    except subprocess.CalledProcessError as e:
        print(f"Ошибка при извлечении зон для {container_id}: {e}")
        return {}

# Получение списка серверов для передачи зон (allow-transfer)
def get_allow_transfer_ips(container_id, zone):
    try:
        result = subprocess.check_output(["docker", "exec", container_id, "cat", "/etc/bind/named.conf"])
        config = result.decode()
        match = re.search(rf'zone "{zone}".*?allow-transfer\s*\{{(.*?)\}};', config, re.DOTALL)
        if match:
            ips = match.group(1).replace(';', '').split()
            return [ip.strip() for ip in ips]
        return []
    except subprocess.CalledProcessError as e:
        print(f"Ошибка при извлечении allow-transfer для зоны {zone}: {e}")
        return []

# Проверка SOA для слейв контейнеров и сверка с мастером
def check_slave_soa(container_id, zone, master_soa):
    try:
        result = subprocess.check_output(["docker", "exec", container_id, "dig", "@localhost", "SOA", zone])
        output = result.decode()
        if master_soa in output:
            print(f"SOA-запрос для слейв {container_id} совпадает с мастером для зоны {zone}")
        else:
            print(f"Ошибка: SOA-запрос для слейв {container_id} не совпадает с мастером для зоны {zone}")
            sys.exit(1)
    except subprocess.CalledProcessError:
        print(f"Ошибка: {container_id} не отвечает на SOA-запросы для зоны {zone}")
        sys.exit(1)

# Основная функция
def main():
    containers = get_containers()

    if not containers:
        print("Нет доступных контейнеров с префиксом dns-test-ci-.")
        sys.exit(1)

    master_data = {}
    print("Начало проверки мастер-контейнеров...")

    # Проверка мастер контейнеров
    for container_id in containers:
        zones = get_zones_from_config(container_id)
        for zone, zone_type in zones.items():
            if zone == ".":
                print(f"Игнорируем зону {zone} для контейнера {container_id}")
                continue

            if zone_type == "master":
                print(f"{container_id} является мастером для зоны {zone}")
                soa_response = check_soa(container_id, zone)
                ns_response = check_ns(container_id, zone)
                master_data[zone] = soa_response
                transfer_ips = get_allow_transfer_ips(container_id, zone)
                print(f"Мастер {container_id} передает зоны {zone} на следующие IP: {transfer_ips}")

    print("Мастер-контейнеры успешно проверены.")

    print("Начало проверки слейв-контейнеров...")

    # Проверка слейв контейнеров и сверка с мастером
    for container_id in containers:
        zones = get_zones_from_config(container_id)
        for zone, zone_type in zones.items():
            if zone == ".":
                print(f"Игнорируем зону {zone} для контейнера {container_id}")
                continue

            if zone_type == "slave" and zone in master_data:
                print(f"{container_id} является слейвом для зоны {zone}")
                check_slave_soa(container_id, zone, master_data[zone])

    print("Все контейнеры проверены успешно.")

if __name__ == "__main__":
    main()
