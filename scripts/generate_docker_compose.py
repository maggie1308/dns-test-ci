import os

# Функция для генерации файла docker-compose.yml на основе данных из servers.txt
def generate_docker_compose():
    # Открываем файл servers.txt и считываем все строки (список серверов)
    with open('../dns-test/servers.txt') as f:
        servers = f.readlines()

    # Начальное содержание для docker-compose.yml
    compose_content = """
    version: '3.7'

    services:
    """

    # Базовый IP-адрес для сети
    base_ip = "172.28"

    # Проходим по каждому серверу в списке servers.txt
    for index, server in enumerate(servers, start=1):
        # Убираем пробелы и символы новой строки
        server = server.strip()
        
        # Генерируем уникальный IP-адрес на основе позиции сервера в списке
        ip = f"{base_ip}.{index}.4"
        
        # Добавляем конфигурацию для каждого сервиса в docker-compose.yml
        compose_content += f"""
        {server}:
            build:
                context: .
                dockerfile: Dockerfile
            volumes:
                - ../dns-test/{server}/etc/bind:/etc/bind
            networks:
                dns-network:
                    ipv4_address: {ip}
        """

    # Добавляем секцию с настройками сети в docker-compose.yml
    compose_content += """
    networks:
      dns-network:
        driver: bridge
        ipam:
          config:
            - subnet: 172.28.0.0/16
    """
    
    # Записываем сгенерированный файл docker-compose.yml
    with open('docker-compose.yml', 'w') as f:
        f.write(compose_content)

# Если скрипт запускается напрямую, то вызываем функцию генерации
if __name__ == "__main__":
    generate_docker_compose()
