import os

# Функция для генерации файла docker-compose.yml на основе данных из servers.txt
def generate_docker_compose():
    # Открываем файл servers.txt для чтения списка хостов и их IP-адресов
    with open('../dns-test/servers.txt') as f:
        servers = f.readlines()  # Читаем все строки файла

    # Начальная часть содержимого файла docker-compose.yml
    compose_content = """
    version: '3.7'

    services:
    """

    # Проходим по каждому серверу из файла servers.txt
    for server in servers:
        # Разделяем строку на имя хоста и IP-адрес
        server_name, ip_address = server.strip().split()
        
        # Формируем блок конфигурации для каждого сервиса на основе имени хоста и IP-адреса
        compose_content += f"""
        {server_name}:
            build:
                context: .
                dockerfile: Dockerfile  # Используем общий Dockerfile для всех сервисов
            volumes:
                - ../dns-test/{server_name}/etc/bind:/etc/bind  # Монтируем конфигурации BIND для каждого хоста
            networks:
                dns-network:
                    ipv4_address: {ip_address}  # Устанавливаем IP-адрес из файла servers.txt
        """

    # Добавляем конфигурацию сети в файл docker-compose.yml
    compose_content += """
    networks:
      dns-network:
        driver: bridge
        ipam:
          config:
            - subnet: 172.28.0.0/16  # Определяем подсеть для контейнеров
    """
    
    # Записываем сформированный docker-compose.yml в файл
    with open('docker-compose.yml', 'w') as f:
        f.write(compose_content)

# Запускаем функцию, если скрипт был вызван напрямую
if __name__ == "__main__":
    generate_docker_compose()
