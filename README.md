# TerraformYandex
# 0) Кратко

**Цель:** поднять в Yandex Cloud учебную инфраструктуру Terraform-ом: VPC/подсеть, 2 ВМ с NAT, Security Groups, управляемый кластер PostgreSQL, сетевой балансировщик (NLB) и сервисы на ВМ:

* **VM1:** Nginx (reverse‑proxy) → Wiki.js (Docker), Netdata.
* **VM2:** Nginx (Docker) со статикой «Hello from VM2».
* **NLB:** балансирует HTTP:80 на обе ВМ (healthcheck `/`).

Выходы (outputs): публичные URL/адреса для Wiki.js, Netdata, VM2 и IP NLB.

---

**Сеть/доступ:**

* SG **web**: вход 22/80/19999 (настраивается `trusted_cidrs`), исходящий - любой.
* SG **db**: вход на 5432/6432 только из подсети `vpc_cidr` (приложения внутри VPC).

---

# 1) Предпосылки

1. **Terraform** ≥ 1.7.1
2. **Yandex Cloud CLI** (`yc`) настроен: `yc init`
3. Создан **Cloud/Folder** и у вас есть права **editor/admin**
4. Сгенерирован SSH‑ключ, публичный путь по умолчанию — `~/.ssh/id_ed25519.pub`

---

# 2) Репо и файлы

```
Terraform/
  main.tf                 # все ресурсы: VPC, SG, Subnet, 2xVM, NLB, MDB-Postgres
  variables.tf            # переменные (в т.ч. netdata_port, db_* и т.д.)
  providers.tf            # блок provider yandex (зона берётся из var.zone)
  outputs.tf              # wiki_url_vm1, app_url_vm2, netdata_url_vm1, load_balancer_ip, db_cluster_fqdn
  nonsecret.auto.tfvars   # НЕсекретные значения (zone, vpc_cidr, vm_*, trusted_cidrs, resource_tags)
  secret.auto.tfvars      # СЕКРЕТЫ (например, db_password)
  secrets.env             # экспорт переменных окружения YC_*
```

> Файл `main.tf` использует модуль `terraform-yc-postgresql` (управляемый PostgreSQL).

---

# 3) Переменные окружения и секреты

## 3.1. `secrets.env` (локально, **в .gitignore**)

```bash
# генерация краткоживущего токена каждый запуск (или подставьте свой OAuth/IAM токен)
export YC_TOKEN="$(yc iam create-token)"
# ваши реальные идентификаторы
export YC_CLOUD_ID="<your_cloud_id>"
export YC_FOLDER_ID="<your_folder_id>"
```

**Как использовать:**

```bash
source Terraform/secrets.env
```

## 3.2. `secret.auto.tfvars` (локально, **в .gitignore**)

```hcl
db_password = "SuperSecret123!"  # пример; используйте сложный пароль
```

## 3.3. `nonsecret.auto.tfvars` (коммитим)

```hcl
zone        = "ru-central1-a"
vpc_cidr    = "10.10.0.0/24"
vm_name     = "hexlet-demo-vm"
vm_cores    = 4
vm_memory   = 4
vm_fraction = 20
trusted_cidrs = ["0.0.0.0/0"]
resource_tags = {
  project     = "hexlet-demo"
  environment = "dev"
}
```

> **Важно:** не кладите команды `export ...` внутрь `*.tfvars` — это HCL, не shell.

---

# 4) Развёртывание

## 4.1. Инициализация окружения

```bash
cd Terraform
source ./secrets.env
```

## 4.2. Инициализация Terraform

```bash
terraform init
```

## 4.3. План

```bash
terraform plan -out tf.plan
```

## 4.4. Применение

```bash
terraform apply tf.plan
```

Ожидаем окончания создания ресурсов (VM, NLB, Managed PostgreSQL). В `metadata.user-data` обе ВМ доустанавливают пакеты и поднимают сервисы (cloud-init).

---

# 5) Результаты и доступ

После `apply` посмотрите выводы:

```bash
terraform output
```

Ключевые:

* `wiki_url_vm1` — Wiki.js через Nginx на VM1.
* `app_url_vm2` — статический сайт на VM2 (Nginx в Docker).
* `netdata_url_vm1` — Netdata веб‑интерфейс (порт из `var.netdata_port`, по умолчанию 19999).
* `load_balancer_ip` — публичный IP сетевого балансировщика.
* `db_cluster_fqdn` — FQDN кластера БД.

Проверки:

```bash
curl -I $(terraform output -raw wiki_url_vm1)
curl -I $(terraform output -raw app_url_vm2)
curl -I $(terraform output -raw netdata_url_vm1)
```

> Healthcheck NLB: HTTP GET `/` на порт 80. Убедитесь, что на обеих ВМ есть ответ `200 OK` по `/`.

---

# 6) Безопасность

* SG **web** пропускает 22/80/19999 из `trusted_cidrs`. Для демонстрации оставлено `0.0.0.0/0`, **в проде сузьте**.
* SG **db** пускает 5432/6432 **только** из подсети `vpc_cidr` (приложения из VPC).
* SSH-логин — ключом (`~/.ssh/id_ed25519.pub`). Парольный вход лучше отключить (доп. hardening вне рамок демо).
* Секреты вынесены из репозитория (`secret.auto.tfvars`, `secrets.env`).

---

# 7) Управление и удаление

Посмотреть ресурсы:

```bash
terraform state list
```

Удалить всё (не забудьте `source secrets.env`):

```bash
terraform destroy -auto-approve
```

---

# 8) Тонкости и замечания

1. **PostgreSQL модуль**: в некоторых версиях параметр `attach_security_group_ids` может отсутствовать — тогда SG применяйте отдельно (см. комментарий в коде).
2. **cloud-init** в `metadata.user-data` ставит Docker/Nginx/Netdata, создаёт site‑конфиг для реверса и запускает Wiki.js в Docker на VM1.
3. **Netdata** настроен на `0.0.0.0` (виден снаружи) — это **для обучения**. В реальных условиях — ограничьте доступ или ставьте VPN/Bastion.
4. **Стабилизация сервисов**: после создания ВМ дайте 1–3 минуты на установку пакетов и старт контейнеров.
5. **Стоимость**: ресурсы оплачиваются по тарифам YC. Не забывайте `destroy`.

---

# 9) Что можно улучшить (для уровня “мидл”)

* **Remote backend** для `tfstate` (Yandex Object Storage, S3 backend).
* **Workspaces** или отдельные стеки для `dev/stage/prod`.
* **CI/CD**: `lint → plan → manual apply → smoke`, автотесты доступности URL, артефакты плана.
* **Hardening**: Fail2ban, UFW/nftables, отключить пароли в SSH, автoобновления безопасности.
* **Мониторинг + Логи**: Prometheus Node Exporter + Grafana (или хотя бы метрики CPU/RAM), логи Nginx в JSON.
* **Секреты**: `sops`/`ansible-vault`; переменные окружения для приложений без хранения в git.

---

# 10) Быстрый старт (шпаргалка)

```bash
# 1) Авторизация в YC и подготовка переменных окружения
yc init
cd Terraform
cp secrets.env.example secrets.env   # если есть шаблон; иначе создайте файл по секции 4.1
source ./secrets.env

# 2) Значения переменных (несекретное)
vim nonsecret.auto.tfvars            # при необходимости скорректируйте

# 3) План/применение
terraform init
terraform plan -out tf.plan
terraform apply tf.plan

# 4) Проверка
terraform output
curl -I $(terraform output -raw load_balancer_ip) | sed -n '1p'

# 5) Удаление
terraform destroy -auto-approve
```

---

# 11) Лицензия и отказ от ответственности

Проект учебный, **без гарантий**. Используйте аккуратно и не забывайте чистить ресурсы, чтобы не тратить бюджет.
