# Только несекретное — это можно коммитить
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
