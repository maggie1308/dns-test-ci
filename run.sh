#!/bin/bash

# Остановка скрипта при первой же ошибке
set -e
echo "Скрипт запущен успешно"
# Перейдем в директорию скриптов (если требуется)
cd "$(dirname "$0")"

# Шаг 1: Проверка изменений в файле servers.txt
CHANGED_FILES=$(git diff --name-only HEAD HEAD~1)

echo "Измененные файлы в последнем коммите: $CHANGED_FILES"

# Проверка, был ли изменен файл servers.txt
if echo "$CHANGED_FILES" | grep -q "servers.txt"; then
    echo "servers.txt был изменен"

    # Шаг 2: Проверка наличия других изменений вне конфигурационных каталогов
    if echo "$CHANGED_FILES" | grep -Ev "servers.txt|ns.*.example.com/.*"; then
        echo "Ошибка: изменения в servers.txt должны сопровождаться изменениями только в соответствующих конфигурациях."
        exit 1
    fi

    # Шаг 3: Генерация конфигурации docker-compose на основе servers.txt
    echo "Генерация docker-compose.yml..."
    python3 scripts/generate_docker_compose.py

    # Шаг 4: Перезапуск контейнеров
    echo "Перезапуск контейнеров..."
    docker-compose down
    docker-compose up -d

    # Шаг 5: Проверка статуса контейнеров
    echo "Проверка статуса контейнеров..."
    docker-compose ps

    # Шаг 6: Выполнение DNS тестов
    echo "Выполнение DNS тестов..."
    bash scripts/perform_dns_tests.sh
else
    echo "servers.txt не был изменен. Выполнение скрипта завершено."
fi

# Если файл servers.txt не изменен, откат на один коммит назад и повторение тестов
if ! echo "$CHANGED_FILES" | grep -q "servers.txt"; then
    echo "Откат на один коммит назад..."
    git reset --hard HEAD~1

    echo "Повторная генерация docker-compose.yml..."
    python3 scripts/generate_docker_compose.py

    echo "Повторный перезапуск контейнеров..."
    docker-compose down
    docker-compose up -d

    echo "Выполнение первоначальных тестов..."
    bash scripts/perform_dns_tests.sh

    echo "Возвращение к последнему коммиту..."
    git reset --hard HEAD@{1}

    echo "Принудительная перезагрузка конфигураций BIND..."
    while IFS= read -r line; do
        server_name=$(echo "$line" | awk '{print $1}')
        echo "Перезагрузка конфигурации BIND для $server_name..."
        docker exec "$server_name" rndc reload
    done < ../dns-test/servers.txt

    echo "Выполнение финальных тестов..."
    bash scripts/perform_dns_tests.sh
fi
