terraform {
  required_version = ">= 1.7.1"
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.150"
    }
  }
}

# Провайдер берёт секреты ИЗ ОКРУЖЕНИЯ:
#   YC_TOKEN, YC_CLOUD_ID, YC_FOLDER_ID, (опц.) YC_ZONE
# Несекретную зону продолжаем задавать через var.zone (ниже).
provider "yandex" {
  zone = var.zone
}
