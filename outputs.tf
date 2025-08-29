output "wiki_url_vm1" {
  description = "Прямой доступ к wiki.js (через Nginx на VM1)"
  value       = "http://${yandex_compute_instance.vm.network_interface[0].nat_ip_address}"
}

output "app_url_vm2" {
  value       = "http://${yandex_compute_instance.vm2.network_interface[0].nat_ip_address}"
  description = "Статическая страница Hello на VM2"
}

output "netdata_url_vm1" {
  value       = "http://${yandex_compute_instance.vm.network_interface[0].nat_ip_address}:${var.netdata_port}"
  description = "Netdata на VM1"
}

output "load_balancer_ip" {
  value = flatten(
    yandex_lb_network_load_balancer.app_lb.listener[*].external_address_spec[*].address
  )[0]
  description = "Публичный IP NLB"
}

output "db_cluster_fqdn" {
  value       = module.yandex-postgresql.cluster_fqdns_list[0][0]
  description = "FQDN первого узла кластера"
}
