# Используем официальный образ Ubuntu как базовый
FROM ubuntu:latest

# Установка необходимых компонентов
RUN apt-get update && apt-get install -y bind9 bind9utils dnsutils

# Создание директории для временных файлов BIND и назначение правильных разрешений
RUN mkdir -p /var/cache/bind/slaves && \
    chown bind:bind /var/cache/bind/slaves && \
    chmod 775 /var/cache/bind/slaves

# Копируем конфигурационные файлы BIND в контейнер
RUN rm -rf /etc/bind
RUN mkdir -p /etc/bind && \
    chown root:bind /etc/bind && \
    chmod 775 /etc/bind

# Настраиваем внутренний порт на 53 для DNS запросов
EXPOSE 53/udp 53/tcp

# Запускаем BIND сервер при старте контейнера
ENTRYPOINT ["/usr/sbin/named"]
CMD ["-g", "-c", "/etc/bind/named.conf", "-u", "bind"]

