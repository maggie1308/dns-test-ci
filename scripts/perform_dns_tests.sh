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
    # Проходим по каждому серверу, указанному в servers.txt
    while read -r line; do
        # Извлекаем имя хоста (первое значение в строке)
        server_name=$(echo $line | awk '{print $1}')
        echo "Checking DNS records for $server_name"
        
        # Проверяем SOA-запись
        docker exec $server_name dig +short SOA example.com
        # Проверяем NS-запись
        docker exec $server_name dig +short NS example.com
        
    done < ../dns-test/servers.txt
}

# Вызываем функцию проверки статуса контейнеров
check_container_status

# Вызываем функцию проверки DNS-записей
check_dns_records
