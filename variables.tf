variable "zone" {
  description = "Yandex Cloud zone"
  type        = string
  default     = "ru-central1-a"
}

variable "vpc_cidr" {
  description = "CIDR для подсети"
  type        = string
  default     = "10.10.0.0/24"
}

variable "vm_name" {
  description = "Имя виртуальной машины"
  type        = string
  default     = "hexlet-demo-vm"
}

variable "vm_cores" {
  description = "vCPU cores"
  type        = number
  default     = 4
}

variable "vm_memory" {
  description = "RAM (GiB)"
  type        = number
  default     = 6
}

variable "vm_fraction" {
  description = "Core fraction"
  type        = number
  default     = 20
}

variable "trusted_cidrs" {
  description = "CIDRs allowed to access services"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "resource_tags" {
  description = "Common labels for resources"
  type        = map(string)
  default = {
    project     = "hexlet-demo"
    environment = "dev"
  }
}

variable "netdata_port" {
  description = "Порт веб-интерфейса Netdata"
  type        = number
  default     = 19999
}

############################################
# PostgreSQL
############################################
variable "db_password" {
  type        = string
  sensitive   = true
  description = "Пароль для PostgreSQL"
}

variable "db_name" {
  type        = string
  default     = "appdb"
  description = "Имя базы данных PostgreSQL"
}

variable "db_user" {
  type        = string
  default     = "appuser"
  description = "Имя пользователя PostgreSQL"
}