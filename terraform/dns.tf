resource "aws_route53_zone" "main" {
  name = "appquadra.com.br"

  tags = merge(local.common_tags, {
    Environment = "shared"
    Name        = "appquadra.com.br"
  })

  # Prevents accidental recreation because a new hosted zone gets different name
  # servers, which would require a manual DNS delegation update at Registro.br.
  lifecycle {
    prevent_destroy = true
  }
}
