resource "libvirt_pool" "lab" {
  name = "lab-pool"
  type = "dir"

  target = {
    path = "/hdd/coding/devops_lab/pool"
  }
}
