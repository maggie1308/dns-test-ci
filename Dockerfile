# Используем официальный образ Ubuntu как базовый
FROM ubuntu:latest

# Установка необходимых компонентов
RUN apt-get update && apt-get install -y bind9 bind9utils dnsutils

# Создание директорий для временных файлов BIND и ключей, назначение правильных разрешений
RUN mkdir -p /var/cache/bind/slaves /run/named && \
    chown bind:bind /var/cache/bind/slaves /run/named && \
    chmod 770 /run/named && \
    chmod 775 /var/cache/bind/slaves

# Копируем конфигурационные файлы BIND в контейнер
RUN rm -rf /etc/bind
RUN mkdir -p /etc/bind && \
    chown root:bind /etc/bind && \
    chmod 775 /etc/bind

# Настраиваем внутренний порт на 53 для DNS запросов
EXPOSE 53/udp 53/tcp

# Запускаем проверку конфигурации и BIND сервер при старте контейнера
CMD ["/bin/bash", "-c", "named-checkconf && /usr/sbin/named -g -c /etc/bind/named.conf -u bind"]
