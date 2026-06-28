output "private_ip" {
  value = aws_network_interface.main.private_ip
}

output "cluster_id" {
  value = var.cluster_id
}

output "instance_id" {
  value = aws_instance.main.id
}

output "data_volume_id" {
  value = aws_ebs_volume.data.id
}
