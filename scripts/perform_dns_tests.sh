#!/bin/bash

# Функция для проверки статуса контейнеров
check_container_status() {
    docker-compose ps  # Выводим статус всех контейнеров
    # Проверяем, что все контейнеры в статусе "Up"
    if [ $(docker-compose ps | grep -c "Up") -eq $(docker-compose ps | grep -c -v "Name") ]; then
        echo "All containers are running."  # Все контейнеры запущены
    else
        echo "Error: Not all containers are running."  # Не все контейнеры запущены
        exit 1  # Завершаем выполнение скрипта с ошибкой
    fi
}

# Функция для проверки DNS-записей
check_dns_records() {
    # Проходим по каждому контейнеру и проверяем DNS-записи
    for container in ns1.example.com ns2.example.com ns3.example.com; do
        echo "Checking DNS records for $container"
        # Проверяем SOA-запись
        docker exec $container dig +short SOA example.com
        # Проверяем NS-запись
        docker exec $container dig +short NS example.com
    done
}

# Вызываем функцию проверки статуса контейнеров
check_container_status

# Вызываем функцию проверки DNS-записей
check_dns_records
