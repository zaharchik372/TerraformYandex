############################################
# Data: свежий образ Ubuntu по семейству
############################################
data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2404-lts"
}

############################################
# Сеть и подсеть
############################################
resource "yandex_vpc_network" "demo" {
  name = "hexlet-demo-net"
  labels = var.resource_tags
}

# Security Group для веб/SSH/Netdata
resource "yandex_vpc_security_group" "web" {
  name       = "hexlet-sg-web"
  network_id = yandex_vpc_network.demo.id
  labels     = var.resource_tags

  # SSH
  ingress {
    protocol       = "TCP"
    description    = "SSH"
    port           = 22
    v4_cidr_blocks = var.trusted_cidrs
  }

  # HTTP
  ingress {
    protocol       = "TCP"
    description    = "HTTP"
    port           = 80
    v4_cidr_blocks = var.trusted_cidrs
  }

  # Netdata
  ingress {
    protocol       = "TCP"
    description    = "Netdata"
    port           = var.netdata_port
    v4_cidr_blocks = var.trusted_cidrs
  }

  # Исходящий трафик
  egress {
    protocol       = "ANY"
    description    = "All outbound"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group Postgres
resource "yandex_vpc_security_group" "db" {
  name       = "hexlet-sg-db"
  network_id = yandex_vpc_network.demo.id
  labels     = var.resource_tags

  # Подключения к Postgres из нашей подсети
  ingress {
    protocol       = "TCP"
    description    = "PostgreSQL"
    port           = 5432
    v4_cidr_blocks = [var.vpc_cidr]
  }

  # PgBouncer
  ingress {
    protocol       = "TCP"
    description    = "PgBouncer"
    port           = 6432
    v4_cidr_blocks = [var.vpc_cidr]
  }

  # Исходящий трафик (обновления и пр.)
  egress {
    protocol       = "ANY"
    description    = "All outbound"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Подсеть
resource "yandex_vpc_subnet" "demo_a" {
  name           = "hexlet-demo-subnet-a"
  zone           = var.zone
  network_id     = yandex_vpc_network.demo.id
  v4_cidr_blocks = [var.vpc_cidr]
  labels         = var.resource_tags
}

############################################
# Managed PostgreSQL кластер
############################################
module "yandex-postgresql" {
  source      = "github.com/terraform-yc-modules/terraform-yc-postgresql?ref=1.0.2"

  name        = "tfhexlet"
  description = "Single-node PostgreSQL cluster for test purposes"
  network_id  = yandex_vpc_network.demo.id

  # Если в версии модуля есть параметр attach_security_group_ids, то SG БД:
  #attach_security_group_ids = [yandex_vpc_security_group.db.id]

  hosts_definition = [
    {
      zone             = var.zone
      assign_public_ip = false
      subnet_id        = yandex_vpc_subnet.demo_a.id
    }
  ]

  postgresql_config = {
    max_connections = 100
  }

  
  databases = [
    {
      name       = "hexlet"
      owner      = var.db_user
      lc_collate = "ru_RU.UTF-8"
      lc_type    = "ru_RU.UTF-8"
      extensions = ["uuid-ossp", "xml2"]
    },
    {
      name       = "hexlet-test"
      owner      = var.db_user
      lc_collate = "ru_RU.UTF-8"
      lc_type    = "ru_RU.UTF-8"
      extensions = ["uuid-ossp", "xml2"]
    }
  ]

  owners = [
    {
      name       = var.db_user
      conn_limit = 15
    }
  ]

  users = [
    {
      name        = "guest"
      conn_limit  = 30
      permissions = ["hexlet"]
      settings = {
        pool_mode                   = "transaction"
        prepared_statements_pooling = true
      }
    }
  ]
}

############################################
# Виртуальная машина 1 (бурстовая)
# VM1: nginx (host) как реверс-прокси к wiki.js (Docker),
#      плюс Netdata (host)
############################################
resource "yandex_compute_instance" "vm" {
  name        = var.vm_name
  platform_id = "standard-v3"
  labels      = var.resource_tags

  resources {
    cores         = var.vm_cores
    memory        = var.vm_memory
    core_fraction = var.vm_fraction
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.image_id
      type     = "network-ssd"
      size     = 15
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.demo_a.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.web.id]
  }

  metadata = {
    ssh-keys  = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
    # cloud-init: ставим docker, nginx, netdata; поднимаем wiki.js;
    # настраиваем реверс 80 -> 127.0.0.1:3000
    user-data = <<-CLOUDCFG
    #cloud-config
    package_update: true
    runcmd:
      - apt-get update
      - apt-get install -y docker.io nginx netdata
      - usermod -aG docker ubuntu

      # Nginx: реверс-прокси к wiki.js (localhost:3000)
      - bash -lc 'cat >/etc/nginx/sites-available/wiki <<NG
server {
  listen 80 default_server;
  server_name _;
  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
  }
}
NG'
      - ln -sf /etc/nginx/sites-available/wiki /etc/nginx/sites-enabled/wiki
      - rm -f /etc/nginx/sites-enabled/default || true
      - systemctl enable --now nginx

      # Netdata слушает 0.0.0.0
      - mkdir -p /etc/netdata
      - bash -lc 'printf "[web]\\n  bind to = 0.0.0.0\\n" > /etc/netdata/netdata.conf'
      - systemctl enable --now netdata

      # Wiki.js контейнер, подключение к MDB через модульные outputs
      - docker run -d --name wiki --restart unless-stopped -p 3000:3000 \
        -e DB_TYPE=postgres \
        -e DB_NAME=${module.yandex-postgresql.databases[0]} \
        -e DB_HOST=${module.yandex-postgresql.cluster_fqdns_list[0][0]} \
        -e DB_PORT=6432 \
        -e DB_USER=${module.yandex-postgresql.owners_data[0].user} \
        -e DB_PASS=${module.yandex-postgresql.owners_data[0].password} \
        ghcr.io/requarks/wiki:2.5
    CLOUDCFG
  }

  # ждём кластер БД из модуля
  depends_on = [module.yandex-postgresql]
}

############################################
# Виртуальная машина 2
############################################
resource "yandex_compute_instance" "vm2" {
  name        = "${var.vm_name}-2"
  platform_id = "standard-v3"
  labels      = var.resource_tags

  resources {
    cores         = var.vm_cores
    memory        = var.vm_memory
    core_fraction = var.vm_fraction
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.image_id
      type     = "network-ssd"
      size     = 15
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.demo_a.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.web.id]
  }

  metadata = {
    ssh-keys  = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
    user-data = <<-CLOUDCFG
    #cloud-config
    runcmd:
      - apt-get update
      - apt-get install -y docker.io
      - usermod -aG docker ubuntu
      - mkdir -p /var/www/html
      - bash -lc 'echo "Hello from VM2" > /var/www/html/index.html'
      - systemctl enable --now docker
      - docker run -d --name app --restart unless-stopped -p 80:80 -v /var/www/html:/usr/share/nginx/html:ro nginx:stable
    CLOUDCFG
  }
}

############################################
# Балансировщик  + Target Group
############################################
resource "yandex_lb_target_group" "app_group" {
  name      = "app-targets"
  region_id = "ru-central1"

  target {
    subnet_id = yandex_vpc_subnet.demo_a.id
    address   = yandex_compute_instance.vm.network_interface[0].ip_address
  }

  target {
    subnet_id = yandex_vpc_subnet.demo_a.id
    address   = yandex_compute_instance.vm2.network_interface[0].ip_address
  }

  labels = var.resource_tags
}

resource "yandex_lb_network_load_balancer" "app_lb" {
  name   = "app-lb"
  labels = var.resource_tags

  listener {
    name = "http-listener"
    port = 80
    external_address_spec {}
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.app_group.id

    healthcheck {
      name = "http"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}

