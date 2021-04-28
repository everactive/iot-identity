data "aws_route53_zone" "domain" {
  zone_id = local.hosted_zone
}

data "kubectl_file_documents" "identity_manifests" {
  content = templatefile(
    "${path.module}/pods/k8s-identity.yaml",
    { IMAGE        = "${local.docker_namespace}/iot-identity:${local.docker_tag}"
      IP_WHITELIST = local.ip_whitelist_public
      MQTTURL      = "${local.mqtt_domain}.${data.aws_route53_zone.domain.name}"
      CERT_ARN     = local.cert_arn
    }
  )
}

resource "kubectl_manifest" "iot_identity" {
  override_namespace = local.namespace
  count              = length(data.kubectl_file_documents.identity_manifests.documents)
  yaml_body          = element(data.kubectl_file_documents.identity_manifests.documents, count.index)
  wait               = true
}

data "kubernetes_service" "iot_identity" {
  depends_on = [
    kubectl_manifest.iot_identity
  ]
  metadata {
    name      = "identity-lb"
    namespace = local.namespace
  }
}

data "aws_elb" "iot_identity" {
  depends_on = [
    kubectl_manifest.iot_identity
  ]
  name = split("-", data.kubernetes_service.iot_identity.status.0.load_balancer.0.ingress.0.hostname)[0]
}

resource "aws_route53_record" "iot_identity" {
  zone_id = local.hosted_zone
  name    = local.identity_domain
  type    = "A"
  alias {
    name                   = data.aws_elb.iot_identity.dns_name
    zone_id                = data.aws_elb.iot_identity.zone_id
    evaluate_target_health = true
  }
}

resource "null_resource" "rollout" {
  depends_on = [
    aws_route53_record.iot_identity
  ]
  triggers = {
    "timestamp" = timestamp()
  }
  provisioner "local-exec" {
    command = <<EOF
      aws eks update-kubeconfig --region ${local.region} --name ${local.eks_cluster};
      kubectl rollout restart deploy identity -n=${local.namespace} ;
    EOF
  }
}