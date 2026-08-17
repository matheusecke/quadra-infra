# quadra-infra

AWS infrastructure for the Quadra platform, provisioned with Terraform, plus the
local Docker Compose environment used for development.

## Production environment

| Component | Address                                                             |
| --------- | ------------------------------------------------------------------- |
| Frontend  | [https://appquadra.com.br](https://appquadra.com.br)                 |
| API       | [https://api.appquadra.com.br](https://api.appquadra.com.br)         |
| API docs  | [https://api.appquadra.com.br/api](https://api.appquadra.com.br/api) |

Single environment named `production`, entirely in `us-east-1`.

```text
              appquadra.com.br
                  Route 53
                      │
        ┌─────────────┴─────────────┐
        │                           │
    quadra-web                  quadra-api
    CloudFront                     ALB
        │                           │
        S3                     ECS Fargate
                                    │
                              RDS PostgreSQL
```

Supporting services: ECR for the API image, Secrets Manager for the database and
JWT credentials, CloudWatch for logs, ACM for both certificates.

The frontend is a static build: CloudFront serves it from a private S3 bucket.
The API runs as a single Fargate task behind the ALB, and the database is never
publicly accessible.

## Terraform

Flat `.tf` files in [`terraform/`](terraform/), one root module, no custom
modules or workspaces. Remote state lives in S3 with encryption, versioning and
the native lockfile.

```bash
export AWS_PROFILE=quadra-admin

cd terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=review.tfplan
terraform apply "review.tfplan"
```

`apply` is always manual and always preceded by a reviewed plan. CI runs only
`fmt -check`, `init -backend=false` and `validate`.

## Deployments

Terraform owns the infrastructure; GitHub Actions owns application releases.
Publishing a new version of the API or the frontend never requires
`terraform apply`.

| Repository     | Trigger         | Pipeline                                                                                                       |
| -------------- | --------------- | -------------------------------------------------------------------------------------------------------------- |
| `quadra-api` | push to`main` | build and push the image to ECR, run migrations in an isolated task, update the ECS Service, verify`/health` |
| `quadra-web` | push to`main` | build with`VITE_API_URL`, sync `dist/` to S3, invalidate CloudFront, verify the public URL                 |

Both authenticate through GitHub OIDC with dedicated least-privilege roles.
There are no permanent AWS keys stored in GitHub.

## Database access

The RDS instance has no public endpoint and accepts connections only from the
ECS security group. Manual access uses AWS CloudShell in VPC mode.

## Local development

Development runs locally against a containerized PostgreSQL, and the local
frontend talks to the local API, never to the AWS one.

Requires Docker and Docker Compose. Clone the repositories side by side:

```text
workspace/
  quadra-api/
  quadra-web/
  quadra-infra/
```

Start the database:

```bash
docker compose up -d
```

PostgreSQL is published on `localhost:5433` and the `quadra-network` bridge is
created here. `quadra-api` and `quadra-web` each have their own Compose file and
join that network, so start them from their own repositories — or run them
directly with `npm run start:dev` and `npm run dev`.

Check that the database is ready:

```bash
docker exec quadra-postgres pg_isready -U postgres -d quadra
```

Connect with psql:

```bash
psql postgresql://postgres:postgres@localhost:5433/quadra
```

## License

All rights reserved — see [LICENSE](LICENSE). Public for academic evaluation and portfolio purposes (TCC); not licensed for external use.
