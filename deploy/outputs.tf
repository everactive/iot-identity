output "identity_url" {
  value = "https://${aws_route53_record.iot_identity.fqdn}"
}
