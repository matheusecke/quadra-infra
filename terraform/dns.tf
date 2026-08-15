resource "aws_route53_zone" "main" {
  name = "appquadra.com.br"

  tags = merge(local.common_tags, {
    Environment = "shared"
    Name        = "appquadra.com.br"
  })

  lifecycle {
    prevent_destroy = true
  }
}
