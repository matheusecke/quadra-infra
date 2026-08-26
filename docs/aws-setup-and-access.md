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
nas quatro subnets; o ECS usa `assign_public_ip = true` explicitamente. Após o
provisionamento da rede, `terraform plan` confirmou que a infraestrutura
corresponde à configuração, sem diferenças.

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
fixos. O endpoint público é exposto somente pelo ALB; a porta `3001` das tasks
continua acessível apenas a partir do Security Group do ALB. Após a criação dos
grupos e regras, `terraform plan` confirmou ausência de diferenças.

### Plataforma de containers

A base necessária para receber futuramente a API foi provisionada:

- **ECR:** repositório privado compartilhado `quadra-api`, com tags imutáveis,
  scan básico no push e criptografia padrão AES-256. A lifecycle policy mantém
  as 10 imagens tagged mais recentes e remove imagens untagged após um dia.
- **ECS Cluster:** `quadra-production-ecs-cluster`, com o serviço pausado
  `quadra-production-api-service`, sem tasks em execução e com Container
  Insights desabilitado para evitar custo adicional nesta fase.
- **CloudWatch Logs:** log group `/ecs/quadra-production-api`, com retenção de
  14 dias.
- **Execution role:** `quadra-production-ecs-execution-role`, com a policy
  gerenciada `AmazonECSTaskExecutionRolePolicy` e acesso de leitura somente aos
  secrets do RDS e do JWT.
- **Task role:** `quadra-production-api-task-role`, com somente as permissões
  `ssmmessages` necessárias ao ECS Exec.
- **Task definition:** família `quadra-production-api`, Fargate `256/512`, com
  container na porta `3001` e imagem inicial `quadra-api:bootstrap`.
- **ECS Service:** `quadra-production-api-service`, com `desired_count = 0`,
  ECS Exec e circuit breaker com rollback habilitados.

As roles de execução e da aplicação permanecem separadas para que permissões da
infraestrutura de inicialização não sejam entregues ao código da API.

### Banco de dados

O RDS PostgreSQL privado `quadra-production-db` foi provisionado nas duas
subnets privadas. A instância usa PostgreSQL `16.14`, classe `db.t4g.micro`,
armazenamento gp3 criptografado e senha master gerenciada pelo Secrets Manager.
Deletion protection está habilitada e o acesso na porta `5432` é permitido
somente a partir do Security Group do ECS.

O acesso administrativo manual é feito pelo AWS CloudShell em modo VPC, usando
o Security Group do ECS. O procedimento completo, incluindo execução de scripts
SQL, está em [`database-access.md`](database-access.md).

### DNS e API pública

- A zona pública `appquadra.com.br` usa os quatro name servers do Route 53,
  delegados no Registro.br.
- O certificado ACM de `api.appquadra.com.br` foi validado por DNS.
- O ALB público `quadra-production-alb` usa as duas subnets públicas e possui
  deletion protection habilitada.
- HTTP na porta `80` redireciona para HTTPS na porta `443`; o listener HTTPS
  encaminha ao target group HTTP na porta `3001`.
- O alias `api.appquadra.com.br` aponta para o ALB.
- O secret `quadra-production-api-jwt-secret` foi criado sem valor e permanece
  protegido por `lifecycle.prevent_destroy`.

O apply da etapa da API criou 13 recursos, sem alterações ou destruições. O
plan executado após o apply confirmou `No changes`. O ALB já gera custo mesmo
com o serviço pausado; não há custo de task Fargate enquanto
`desired_count = 0`.

### Pausa e retomada do ambiente

O repositório contém o mecanismo de operação, mas o EventBridge Scheduler só
passa a existir depois de um `terraform apply` manual. Nenhum `apply` ou comando
real de pausa/retomada é executado automaticamente pelo CI.

Pré-requisitos locais:

- Bash 5, AWS CLI v2 e `curl`;
- sessão AWS autenticada, normalmente com `AWS_PROFILE=quadra-admin`;
- identidade na conta `141145164743` e região `us-east-1`;
- Scheduler já provisionado pelo Terraform.

Consultar o estado não altera recursos:

```bash
./scripts/aws-environment.sh status
```

Pausar reduz o ECS para zero, espera o serviço estabilizar, para o RDS e só
então habilita o Scheduler diário:

```bash
./scripts/aws-environment.sh pause
```

Retomar desabilita primeiro o Scheduler, inicia e aguarda o RDS ficar
`available`, sobe uma task ECS e só termina depois de serviço estável, target
saudável e `https://api.appquadra.com.br/health` responder HTTP 200:

```bash
./scripts/aws-environment.sh resume
```

Cada operação mostra o estado inicial, transitório e final do RDS. Código de
saída `1` indica entrada, autenticação, recurso, AWS CLI ou health check com
falha; código `2` indica estado transitório, inválido ou combinação operacional
inconsistente. Não há rollback automático: após estado parcial, corrigir a
causa, consultar `status` e decidir explicitamente entre repetir `pause` ou
`resume`.

Durante `pause` e `resume`, o script mostra etapas numeradas e timestamps antes
e depois das esperas da AWS. Enquanto o RDS está parando, o estado é consultado
a cada 30 segundos por até 30 minutos. As cores são usadas somente no terminal
e podem ser desativadas com `NO_COLOR=1`; saídas redirecionadas permanecem sem
códigos ANSI.

O RDS parado é reiniciado automaticamente pela AWS depois de sete dias. Por
isso, enquanto o ambiente está intencionalmente pausado, um EventBridge
Scheduler diário às `03:00 UTC` reaplica `StopDBInstance` diretamente, sem
Lambda. `resume` o desabilita antes de iniciar o banco.

A pausa não elimina cobranças de ALB, armazenamento e backups do RDS, S3, ECR,
Route 53, Secrets Manager ou logs. Ela interrompe somente a computação das
tasks Fargate e da instância RDS enquanto esta permanecer parada.

Para ativar o mecanismo pela primeira vez, em uma sessão operacional separada:

1. revisar um `terraform plan` novo;
2. aplicar somente após aprovação humana explícita;
3. confirmar que o schedule foi criado como `DISABLED`;
4. executar `./scripts/aws-environment.sh status` antes de qualquer operação;
5. executar `pause` ou `resume` somente após revisar o estado reportado;
6. executar `status` novamente e conferir o estado final.

### Hospedagem do frontend

- O bucket `quadra-production-frontend-141145164743` armazena o build do
  `quadra-web` e tem bloqueio completo de acesso público.
- O Origin Access Control `E1HU77L175CA5V` é o único caminho de leitura do
  bucket; a bucket policy autoriza `s3:GetObject` apenas ao principal do
  CloudFront e apenas para o ARN desta distribuição.
- A distribuição CloudFront `EUL2VBY6P6R7Q` serve `appquadra.com.br`, com
  `index.html` como default root object e `403`/`404` mapeados para
  `/index.html` com HTTP 200 (fallback de SPA).
- O certificado ACM de `appquadra.com.br` foi validado por DNS.
- Os aliases `A` e `AAAA` do domínio raiz apontam para a distribuição.
- A role `quadra-production-web-deploy-role` é assumida por OIDC pelo
  `quadra-web` em `refs/heads/main` e pode apenas listar e escrever no bucket do
  frontend e criar invalidações nessa distribuição.

O apply da etapa do frontend criou 12 recursos, sem alterações ou destruições.
Verificado depois do apply: o domínio resolve em IPv4 e IPv6, o TLS usa o
certificado novo e a requisição é atendida pelo edge `GRU3` (São Paulo). Não há
custo fixo nesta etapa: o volume do projeto fica dentro do free tier permanente
do CloudFront e o armazenamento no S3 é de alguns MB.

O primeiro deploy do `quadra-web` foi publicado pelo GitHub Actions e o
frontend está no ar. Verificado depois do deploy:

- `https://appquadra.com.br` responde HTTP 200 com `cache-control: no-cache` no
  `index.html`;
- `https://appquadra.com.br/tournaments/1` — rota que não existe como objeto no
  bucket — responde HTTP 200 com `text/html`, confirmando o fallback de SPA;
- os bundles em `/assets/` respondem com
  `cache-control: public, max-age=31536000, immutable`;
- o bundle publicado aponta para `https://api.appquadra.com.br`;
- carregada em um navegador, a aplicação inicializa, chama
  `POST https://api.appquadra.com.br/auth/refresh`, recebe `401` por não haver
  sessão e redireciona para a tela de login — o caminho frontend → API funciona
  de ponta a ponta, com DNS, TLS, CORS e credenciais.

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
