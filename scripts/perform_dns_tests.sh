#!/bin/bash

# Функция для проверки статуса контейнеров
check_container_status() {
    docker-compose ps
    # Проверяем, что все контейнеры запущены
    if [ $(docker-compose ps | grep -c "Up") -eq $(docker-compose ps | grep -c -v "Name") ]; then
        echo "All containers are running."
    else
        echo "Error: Not all containers are running."
        exit 1
    fi
}

# Функция для проверки DNS записей
check_dns_records() {
    for container in ns1.example.com ns2.example.com ns3.example.com; do
        echo "Checking DNS records for $container"
        # Проверяем SOA запись
        docker exec $container dig +short SOA example.com
        # Проверяем NS запись
        docker exec $container dig +short NS example.com
    done
}

# Выполняем проверки
check_container_status
check_dns_records
