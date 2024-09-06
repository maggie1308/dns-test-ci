#!/bin/bash

# Остановка скрипта при ошибке
set -e

echo "Скрипт запущен успешно"

# Чтение файла servers.txt для извлечения хостов и их IP-адресов
declare -A HOSTS_IPS
while IFS= read -r line; do
    host=$(echo $line | awk '{print $1}')
    ip=$(echo $line | awk '{print $2}')
    HOSTS_IPS[$host]=$ip
done < servers.txt

# Функция для сравнения зон SOA
compare_soa() {
    local master_soa=$1
    local slave_soa=$2
    if [[ "$master_soa" == "$slave_soa" ]]; then
        echo "SOA записи совпадают."
    else
        echo "Ошибка: SOA записи не совпадают."
        exit 1
    fi
}

# Добавление удаленного репозитория и извлечение данных
git remote add dns-test https://github.com/maggie1308/dns-test.git || echo "Remote 'dns-test' уже добавлен"
git fetch dns-test

# Получение последнего коммита из репозитория dns-test
LAST_COMMIT_HASH=$(git rev-parse dns-test/main)
PREV_COMMIT_HASH=$(git rev-parse dns-test/main~1)
echo "Последний коммит в dns-test: $LAST_COMMIT_HASH"

# Получение списка измененных файлов между последним и предыдущим коммитами
CHANGED_FILES=$(git diff --name-only $PREV_COMMIT_HASH $LAST_COMMIT_HASH | sed 's/\\302\\240//g' | tr -d '"')
echo "Измененные файлы в последнем коммите репозитория dns-test: $CHANGED_FILES"

# Проверяем, был ли изменен файл servers.txt
if echo "$CHANGED_FILES" | grep -q "servers.txt"; then
    echo "servers.txt был изменен"

    # Извлекаем список новых или измененных хостов из файла servers.txt
    NEW_HOSTS=$(git diff $PREV_COMMIT_HASH $LAST_COMMIT_HASH -- servers.txt | grep '^+' | grep -v '^+++' | awk '{print $1}' | sed 's/^+//')
    
    # Проверяем наличие других изменений вне каталогов новых хостов
    for file in $CHANGED_FILES; do
        if [[ "$file" != "servers.txt" ]]; then
            is_valid=false

            # Убираем неразрывные пробелы и обрезаем строку до первого слэша
            CLEANED_FILE_PREFIX=$(echo "$file" | sed 's/\\302\\240//g' | cut -d'/' -f1)

            for host in $NEW_HOSTS; do
                # Если обрезанный путь совпадает с именем нового хоста, изменения допустимы
                if [[ "$CLEANED_FILE_PREFIX" == "$host" ]]; then
                    is_valid=true
                    echo "Измененный файл конфигурации для $host: $file - Верно"
                    break
                fi
            done

            # Если изменения не связаны с поддиректорией нового хоста, выводим ошибку
            if ! $is_valid; then
                echo "Ошибка: Изменения в \"$file\" не связаны с новыми или измененными хостами."
                exit 1
            fi
        fi
    done

    # Проверка, чтобы каждый новый хост имел изменения в своей директории
    for host in $NEW_HOSTS; do
        has_changes=false
        for file in $CHANGED_FILES; do
            CLEANED_FILE_PREFIX=$(echo "$file" | sed 's/\\302\\240//g' | cut -d'/' -f1)
            if [[ "$CLEANED_FILE_PREFIX" == "$host" ]]; then
                has_changes=true
                break
            fi
        done
        if ! $has_changes; then
            echo "Ошибка: Хост \"$host\" добавлен в servers.txt, но нет соответствующих изменений в конфигурации."
            exit 1
        fi
    done

    # Шаги 1.2.1 - 1.2.5: Создание и проверка контейнеров
    echo "Генерация docker-compose.yml..."
    python3 scripts/generate_docker_compose.py  # Создаем docker-compose файл

    echo "Перезапуск контейнеров..."
    docker-compose up -d --build  # Перезапускаем контейнеры

    echo "Проверка статуса контейнеров..."
    docker-compose ps  # Проверяем, что все контейнеры работают

    echo "Проверка SOA и NS для master-контейнеров..."

    # Получаем список запущенных контейнеров и проверяем соответствие с новыми хостами
    for host in "${!HOSTS_IPS[@]}"; do
        container_id=$(docker ps --filter "name=$host" --format "{{.Names}}")
        if [[ -z "$container_id" ]]; then
            echo "Ошибка: контейнер для $host не найден."
            exit 1
        fi

        # Проверяем SOA и NS для каждого контейнера
        echo "Проверка SOA для $host (контейнер $container_id)..."
        master_soa=$(docker exec "$container_id" dig SOA "$host" +short)
        echo "SOA для $host: $master_soa"

        echo "Проверка NS для $host (контейнер $container_id)..."
        docker exec "$container_id" dig NS "$host" +short || { echo "Ошибка: $host не отвечает на NS-запросы"; exit 1; }

        echo "Проверка SOA для slave-контейнеров..."
        for host in "${!HOSTS_IPS[@]}"; do
            container_id=$(docker ps --filter "name=$host" --format "{{.Names}}")
            slave_soa=$(docker exec "$container_id" dig SOA "$host" +short)
            compare_soa "$master_soa" "$slave_soa"
        done
    done
fi
