import os

def generate_docker_compose():
    # Открываем файл servers.txt и читаем его содержимое
    with open('../dns-test/servers.txt') as f:
        servers = f.readlines()

    # Начальная часть файла docker-compose.yml
    compose_content = """
    version: '3.7'

    services:
    """
    # Добавляем конфигурацию для каждого сервера из servers.txt
    for server in servers:
        server = server.strip()
        ip = f"172.28.{servers.index(server)+1}.1"
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

    # Конфигурация сети
    compose_content += """
    networks:
      dns-network:
        driver: bridge
        ipam:
          config:
            - subnet: 172.28.0.0/16
    """
    
    # Записываем сгенерированный контент в файл docker-compose.yml
    with open('docker-compose.yml', 'w') as f:
        f.write(compose_content)

if __name__ == "__main__":
    generate_docker_compose()
