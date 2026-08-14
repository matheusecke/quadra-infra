# Setup e acesso à AWS

Estado operacional confirmado da configuração AWS usada pelo projeto Quadra.
Decisões arquiteturais e direcionamentos futuros permanecem registrados no
[`ROADMAP.md`](ROADMAP.md).

## Conta AWS

- **AWS Account ID:** `141145164743`
- **Região principal:** `us-east-1`
- A conta root existe, mas não deve ser utilizada nas operações normais do
  projeto.
- MFA está configurado para o acesso utilizado no dia a dia.

## Administração local

- **IAM user:** `matheusecke`
- **IAM group:** `quadra-admins`
- Policies associadas por meio do grupo:
  - `AdministratorAccess`
  - `SignInLocalDevelopmentAccess`

`AdministratorAccess` está sendo utilizada nesta fase inicial para simplificar
o provisionamento e o aprendizado. As permissões poderão ser restringidas
posteriormente seguindo o princípio de menor privilégio.

## Autenticação local

- A AWS CLI está instalada localmente.
- A autenticação é feita com `aws login`.
- Não foram criadas Access Key e Secret Access Key permanentes para o
  desenvolvimento local.
- **Profile AWS:** `quadra-admin`
- **Identidade associada:**
  `arn:aws:iam::141145164743:user/matheusecke`
- A identidade foi validada com:

  ```bash
  aws sts get-caller-identity
  ```

Durante uma sessão de trabalho, AWS CLI e Terraform podem utilizar esse profile
por padrão por meio de:

```bash
export AWS_PROFILE=quadra-admin
```

## Terraform local

- O Terraform está instalado localmente.
- **Versão verificada no início do processo:** `Terraform v1.15.8`
- **Plataforma:** `linux_amd64`
- **Diretório do Terraform:** `terraform/`
- No início do processo, o diretório estava vazio e nenhum recurso da aplicação
  havia sido provisionado.

## Estado atual da infraestrutura

- O bucket S3 `quadra-terraform-state-141145164743` foi provisionado em
  `us-east-1` para armazenar o state do Terraform.
- O bucket possui versionamento habilitado e bloqueio completo de acesso
  público.
- A configuração Terraform protege o bucket contra destruição acidental com
  `lifecycle.prevent_destroy`.
- O backend remoto S3 está configurado com a chave
  `production/terraform.tfstate` e criptografia habilitada.
- O locking utiliza o lockfile nativo do backend S3 (`use_lockfile = true`), sem
  tabela DynamoDB.
- O state criado durante o bootstrap foi migrado do backend local para o S3.
- Após a migração, `terraform plan` confirmou ausência de diferenças e liberou
  o state lock normalmente.
- Um backup local anterior à migração foi armazenado em
  `terraform/.state-backups/`, diretório ignorado pelo Git.

### Rede da aplicação

A fundação de rede do ambiente `production` foi provisionada com Terraform:

- **VPC:** `vpc-0cfb1beb1d75d1142`, CIDR `10.0.0.0/16`, com suporte e
  hostnames DNS habilitados.
- **Subnet pública A:** `subnet-0375710b2838a8acb`, `us-east-1a`, CIDR
  `10.0.1.0/24`.
- **Subnet pública B:** `subnet-0bec1c5b85075d7bd`, `us-east-1b`, CIDR
  `10.0.2.0/24`.
- **Subnet privada A:** `subnet-0d614b2a1969257b7`, `us-east-1a`, CIDR
  `10.0.11.0/24`.
- **Subnet privada B:** `subnet-08b3e66f236eb2dbf`, `us-east-1b`, CIDR
  `10.0.12.0/24`.
- **Internet Gateway:** `igw-05e8decbac23dcc5d`, associado à VPC.
- **Route table pública:** `rtb-0f08f3fcaebd9b284`, com rota
  `0.0.0.0/0` para o Internet Gateway e associação às duas subnets públicas.
- **Route table privada:** `rtb-0cf59786f0c60ae4a`, associada às duas
  subnets privadas e sem rota para a internet.

Não existe NAT Gateway. A atribuição automática de IP público está desabilitada
nas quatro subnets; o ECS deverá usar `assign_public_ip = true` explicitamente
quando for implementado. Após o provisionamento da rede, `terraform plan`
confirmou que a infraestrutura corresponde à configuração, sem diferenças.

### Security Groups da aplicação

Os Security Groups planejados para os componentes da aplicação foram
provisionados na VPC do ambiente `production`:

- **ALB:** `quadra-production-alb-sg` (`sg-0c34cf4762936407f`). Aceita tráfego
  público TCP nas portas `80` e `443` e permite saída TCP `3001` somente para o
  Security Group do ECS.
- **ECS:** `quadra-production-ecs-sg` (`sg-061558ae133a81fc0`). Aceita entrada
  TCP `3001` somente do Security Group do ALB. Permite saída TCP `443` para
  serviços AWS e APIs HTTPS e TCP `5432` somente para o Security Group do RDS.
- **RDS:** `quadra-production-rds-sg` (`sg-018a8c7c5b0997adc`). Aceita entrada
  TCP `5432` somente do Security Group do ECS e não possui regra de saída.

As relações internas utilizam referências entre Security Groups, sem IPs
fixos. O acesso público configurado no grupo do ALB não expõe atualmente um
endpoint, pois o ALB ainda não foi provisionado. Após a criação dos grupos e
regras, `terraform plan` confirmou ausência de diferenças.

Nenhum recurso de aplicação, banco de dados ou computação foi provisionado até
este ponto.

## Segurança

Não registrar neste repositório:

- senhas;
- códigos, QR codes ou seeds de MFA;
- Access Key, Secret Access Key ou session token;
- authorization codes, cookies ou credenciais temporárias;
- secrets da aplicação;
- tokens emitidos durante autenticação;
- valores sensíveis do Terraform.

Outputs utilizados durante o provisionamento devem ser sanitizados antes de
serem adicionados a este documento.
