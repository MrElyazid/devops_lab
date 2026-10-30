output "web_ip" {
  value = "10.10.10.10"
}

output "k3s_master_ip" {
  value = "10.10.10.40"
}

output "k3s_worker_ip" {
  value = "10.10.10.41"
}

output "mon_ip" {
  value = "10.10.10.30"
}

output "grafana_url" {
  value = "http://10.10.10.30:3000"
}

output "prometheus_url" {
  value = "http://10.10.10.30:9090"
}

output "haproxy_stats" {
  value = "http://10.10.10.10:8404"
}

output "curl_items" {
  value = "curl http://10.10.10.10/items"
}
