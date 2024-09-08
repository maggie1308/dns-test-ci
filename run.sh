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

#!/usr/local/bin/bash


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

    python3 soa_ns_check_script.py  

else
    echo "Файл servers.txt не изменен."
   

    # Получение последнего и предыдущего коммитов
    LAST_COMMIT_HASH=$(git rev-parse dns-test/main)
    PREV_COMMIT_HASH=$(git rev-parse dns-test/main~1)

    # Получение списка измененных файлов между последним и предыдущим коммитами
    CHANGED_FILES=$(git diff --name-only $PREV_COMMIT_HASH $LAST_COMMIT_HASH | sed 's/\\302\\240//g' | tr -d '"')
    echo "Измененные файлы в последнем коммите репозитория dns-test: $CHANGED_FILES"

    # Инициализируем список для хранения изменённых контейнеров
    CHANGED_CONTAINERS=()

    # Проход по измененным файлам
    for file in $CHANGED_FILES; do
        if [[ "$file" != "servers.txt" ]]; then
            # Убираем неразрывные пробелы и обрезаем строку до первого слэша
            CLEANED_FILE_PREFIX=$(echo "$file" | sed 's/\\302\\240//g' | cut -d'/' -f1)
        
            # Если папка (контейнер) еще не добавлена, добавляем её в список
            if [[ ! " ${CHANGED_CONTAINERS[@]} " =~ " ${CLEANED_FILE_PREFIX} " ]]; then
                CHANGED_CONTAINERS+=("$CLEANED_FILE_PREFIX")
            fi
        fi
    done

    # Проверка, есть ли изменённые контейнеры
    if [ ${#CHANGED_CONTAINERS[@]} -eq 0 ]; then
        echo "Нет измененных контейнеров"
        exit 0
    fi

    # Преобразуем список контейнеров в строку с пробелами (для передачи в Python-скрипт)
    CHANGED_CONTAINERS_STR=$(IFS=" " ; echo "${CHANGED_CONTAINERS[*]}")

    # Вызов Python-скрипта с изменёнными контейнерами
    #python3 /path/to/your/python_script.py $CHANGED_CONTAINERS_STR

fi
