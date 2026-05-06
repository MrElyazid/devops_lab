resource "libvirt_network" "lab" {
  name = "lab-net"
  forward = {
    mode = "nat"
  }
  domain = {
    name = "lab.local"
  }
  ips = [{
    address = "10.10.10.1"
    netmask = "255.255.255.0"
    dhcp = {
      ranges = [{
        start = "10.10.10.50"
        end   = "10.10.10.200"
      }]
    }
  }]
  dns = {
    enable = "yes"
  }
}
