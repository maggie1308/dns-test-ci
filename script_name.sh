#!/bin/bash

# Остановка скрипта при ошибке
set -e

# Функция для чтения и анализа конфигурационного файла
analyze_config() {
    local container_name=$1

    echo "Чтение конфигурации для $container_name..."
    docker exec "$container_name" cat /etc/bind/named.conf > /tmp/named.conf.$container_name

    # Определение мастер-зон
    echo "Мастер-зоны для $container_name:"
    grep -B 1 'type master;' /tmp/named.conf.$container_name | grep 'zone' | awk '{print $2}' | tr -d '"' || echo "Нет мастер-зон"

    # Определение слейв-зон
    echo "Слейв-зоны для $container_name:"
    grep -B 1 'type slave;' /tmp/named.conf.$container_name | grep 'zone' | awk '{print $2}' | tr -d '"' || echo "Нет слейв-зон"
}

# Функция для проверки зон
check_zones() {
    local container_name=$1
    local zones=$2
    local type=$3

    for zone in $zones; do
        echo "Проверка $type зоны $zone для $container_name..."
        docker exec "$container_name" dig @localhost SOA "$zone" || { echo "Ошибка: $zone не отвечает на SOA-запросы"; exit 1; }
        if [ "$type" = "мастер" ]; then
            docker exec "$container_name" dig @localhost NS "$zone" || { echo "Ошибка: $zone не отвечает на NS-запросы"; exit 1; }
        fi
    done
}

# Массив с именами контейнеров
containers=("dns-test-ci-ns1.example.com-1" "dns-test-ci-ns2.example.com-1" "dns-test-ci-ns3.example.com-1")

for container in "${containers[@]}"; do
    # Чтение конфигурации и определение мастер- и слейв-зон
    master_zones=$(analyze_config "$container" | grep 'Мастер-зоны' -A 10 | tail -n +2)
    slave_zones=$(analyze_config "$container" | grep 'Слейв-зоны' -A 10 | tail -n +2)

    # Проверка мастер-зон
    if [ -n "$master_zones" ]; then
        check_zones "$container" "$master_zones" "мастер"
    fi

    # Проверка слейв-зон
    if [ -n "$slave_zones" ]; then
        check_zones "$container" "$slave_zones" "слейв"
    fi
done

echo "Проверка завершена успешно."
# Получаем список запущенных контейнеров и проверяем соответствие с новыми хостами
    for host in $NEW_HOSTS; do
        container_id=$(docker ps --filter "name=$host" --format "{{.Names}}")
        if [[ -z "$container_id" ]]; then
            echo "Ошибка: контейнер для $host не найден."
            exit 1
        fi

        # Проверяем SOA и NS для каждого контейнера
        echo "Проверка SOA для $host (контейнер $container_id)..."
        docker exec "$container_id" dig SOA "$host" || { echo "Ошибка: $host не отвечает на SOA-запросы"; exit 1; }
        echo "Проверка NS для $host (контейнер $container_id)..."
        docker exec "$container_id" dig NS "$host" || { echo "Ошибка: $host не отвечает на NS-запросы"; exit 1; }
    done

    echo "Проверка SOA для slave-контейнеров..."
    for host in $NEW_HOSTS; do
        container_id=$(docker ps --filter "name=$host" --format "{{.Names}}")
        docker exec "$container_id" dig SOA "$host" || { echo "Ошибка: $host не отвечает на SOA-запросы для slave"; exit 1; }
    done

else