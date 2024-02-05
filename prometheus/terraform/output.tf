# https://www.terraform.io/language/values/outputs

output "prometheus_public_ip" {
  value = aws_instance.monitoring_stack_lab.public_ip
  description = "The prometheus stack public ip address"
}
