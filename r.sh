#!/usr/local/bin/bash


# Остановка скрипта при первой же ошибке
set -e

echo "Скрипт запущен успешно"

# Добавление удаленного репозитория и извлечение данных
git remote add dns-test https://github.com/maggie1308/dns-test.git || echo "Remote 'dns-test' уже добавлен"
git fetch dns-test

# Получение последнего коммита из репозитория dns-test
LAST_COMMIT_HASH=$(git rev-parse dns-test/main)
PREV_COMMIT_HASH=$(git rev-parse dns-test/main~1)
echo "Последний коммит в dns-test: $LAST_COMMIT_HASH"

#Шаг 1: Парсинг всех хостов и IP-адресов из файла servers.txt
echo "Парсинг файла servers.txt..."
declare -A HOSTS_IPS
if [ -f "servers.txt" ]; then
    while read -r line; do
        host=$(echo "$line" | awk '{print $1}')
        ip=$(echo "$line" | awk '{print $2}')
        if [ -n "$host" ] && [ -n "$ip" ]; then
            HOSTS_IPS["$host"]="$ip"
        fi
    done < servers.txt

    # Вывод всех хостов и их IP для проверки
    echo "Все хосты и IP-адреса:"
    for host in "${!HOSTS_IPS[@]}"; do
        echo "$host -> ${HOSTS_IPS[$host]}"
    done
else
    echo "Ошибка: файл servers.txt не найден!"
    exit 1
fi

# Получение списка измененных файлов между последним и предыдущим коммитами
CHANGED_FILES=$(git diff --name-only $PREV_COMMIT_HASH $LAST_COMMIT_HASH | sed 's/\\302\\240//g' | tr -d '"')
echo "Измененные файлы в последнем коммите репозитория dns-test: $CHANGED_FILES"

# Проверяем, был ли изменен файл servers.txt
if echo "$CHANGED_FILES" | grep -q "servers.txt"; then
    echo "servers.txt был изменен"

    # Извлекаем список новых или измененных хостов из файла servers.txt
    NEW_HOSTS=$(git diff $PREV_COMMIT_HASH $LAST_COMMIT_HASH -- servers.txt | grep '^+' | grep -v '^+++' | awk '{print $1}' | sed 's/^+//')
    
    # Выводим список новых или измененных хостов
    echo "Новые или измененные хосты: $NEW_HOSTS"

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

    # Проверка, чтобы каждый новый хост имел хотя бы одно изменение в своей директории
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

    # Проверка, является ли контейнер мастером или слейвом
    for host in $NEW_HOSTS; do
        container_id=$(docker ps --filter "name=$host" --format "{{.Names}}")
        
        # Проверяем конфигурацию контейнера для определения его роли
        if docker exec "$container_id" grep -q "type master;" /etc/bind/named.conf; then
            echo "$container_id является мастер-контейнером"
            ROLE="master"
        elif docker exec "$container_id" grep -q "type slave;" /etc/bind/named.conf; then
            echo "$container_id является слейв-контейнером"
            ROLE="slave"
        else
            echo "Ошибка: не удалось определить роль контейнера $container_id"
            exit 1
        fi

        # Дальнейшая обработка в зависимости от роли контейнера
        if [[ "$ROLE" == "master" ]]; then
            # Проверка для мастер-контейнеров
            echo "Проверка SOA для $container_id (контейнер $container_id)..."
            docker exec "$container_id" dig @localhost SOA example.com || { echo "Ошибка: $host не отвечает на SOA-запросы"; exit 1; }

            echo "Проверка NS для $container_id (контейнер $container_id)..."
            docker exec "$container_id" dig @localhost NS example.com || { echo "Ошибка: $host не отвечает на NS-запросы"; exit 1; }
        elif [[ "$ROLE" == "slave" ]]; then
            # Проверка для слейв-контейнеров
            echo "Проверка SOA для слейв-контейнера $container_id..."
            docker exec "$container_id" dig @localhost SOA example.com || { echo "Ошибка: $host не отвечает на SOA-запросы для slave"; exit 1; }
        fi
    done

else
    echo "Файл servers.txt не изменен. Завершение работы скрипта."
fi
