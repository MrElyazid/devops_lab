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

output "ssh_web" {
  value = "ssh ubuntu@10.10.10.10"
}

output "ssh_api_01" {
  value = "ssh ubuntu@10.10.10.11"
}

output "ssh_api_02" {
  value = "ssh ubuntu@10.10.10.13"
}

output "ssh_db" {
  value = "ssh ubuntu@10.10.10.12"
}

output "curl_items" {
  value = "curl http://10.10.10.10/items"
}

output "haproxy_stats" {
  value = "http://10.10.10.10:8404"
}
