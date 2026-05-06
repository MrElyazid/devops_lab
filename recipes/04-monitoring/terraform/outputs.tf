output "web_ip" {
  value = "10.10.10.10"
}

output "api_01_ip" {
  value = "10.10.10.11"
}

output "api_02_ip" {
  value = "10.10.10.13"
}

output "db_ip" {
  value = "10.10.10.12"
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

output "curl_items" {
  value = "curl http://10.10.10.10/items"
}
