import json
import sys

# Загрузка данных из JSON
with open(sys.argv[1], 'r') as f:
    old_soa = json.load(f)

with open(sys.argv[2], 'r') as f:
    new_soa = json.load(f)

# Сравнение SOA-записей
for old_entry in old_soa:
    master_ip = list(old_entry.keys())[0]
    old_zones = old_entry[master_ip]

    for new_entry in new_soa:
        if master_ip in new_entry:
            new_zones = new_entry[master_ip]

            for zone_name, old_soa_value in old_zones.items():
                new_soa_value = new_zones.get(zone_name)

                if new_soa_value:
                    old_serial = int(old_soa_value.split()[2])
                    new_serial = int(new_soa_value.split()[2])
                    
                    if new_serial > old_serial:
                        print(f"SOA для зоны {zone_name} увеличилась: {old_serial} -> {new_serial}")
                    else:
                        print(f"Ошибка: SOA для зоны {zone_name} не увеличилась: {old_serial} -> {new_serial}")
