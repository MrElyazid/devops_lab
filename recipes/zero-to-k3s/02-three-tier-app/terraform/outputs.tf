output "web_ip" {
  value = "10.10.10.10"
}

output "api_ip" {
  value = "10.10.10.11"
}

output "db_ip" {
  value = "10.10.10.12"
}

output "ssh_web" {
  value = "ssh ubuntu@10.10.10.10"
}

output "ssh_api" {
  value = "ssh ubuntu@10.10.10.11"
}

output "ssh_db" {
  value = "ssh ubuntu@10.10.10.12"
}

output "curl_items" {
  value = "curl http://10.10.10.10/items"
}
