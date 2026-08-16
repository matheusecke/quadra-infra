# Evolução de CI/CD na AWS

Estratégia progressiva de adoção de CI/CD do projeto Quadra. Este documento
registra o estado atual, as próximas etapas decididas e evoluções opcionais dos
pipelines dos repositórios `quadra-api`, `quadra-web` e `quadra-infra`.

As decisões gerais de infraestrutura permanecem no [`ROADMAP.md`](ROADMAP.md),
enquanto o estado operacional da conta e dos acessos AWS está em
[`aws-setup-and-access.md`](aws-setup-and-access.md).

## Responsabilidades

- **Terraform:** cria e configura a infraestrutura, ou seja, o que existe na
  AWS.
- **GitHub Actions da API e do frontend:** valida, publica e implanta novas
  versões das aplicações na infraestrutura existente.
- **GitHub Actions da infraestrutura:** inicialmente valida o código Terraform
  e poderá também apresentar o `terraform plan` para revisão.

Publicar uma nova versão da API ou do frontend não deve depender de
`terraform apply`.

## Estado atual

```text
quadra-api
└── CI existente
    └── sem CD AWS

quadra-web
└── CI existente
    └── sem CD AWS

quadra-infra
└── Terraform manual
    └── sem GitHub Actions
```

Esse estado é intencional. Os workflows existentes da API e do frontend
validam suas respectivas aplicações, mas ainda não publicam artefatos na AWS.
No repositório de infraestrutura, o Terraform será usado local e manualmente
durante a fase inicial.

A execução manual permite compreender antes da automação:

- `terraform init`;
- `terraform fmt`;
- `terraform validate`;
- `terraform plan`;
- `terraform apply`;
- state;
- backend remoto;
- locking;
- efeitos reais das alterações na AWS.

A automação será introduzida progressivamente para não ocultar esses conceitos
durante o aprendizado.

## Evolução planejada

### Fase 1 — Terraform manual

**Status: estado inicial decidido.**

Os comandos serão executados local e manualmente:

```text
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

O `terraform plan` sempre será revisado antes de qualquer `terraform apply`.
Essa fase tem como objetivos:

- aprender o ciclo do Terraform;
- estabelecer o remote state e o locking;
- criar os primeiros recursos;
- observar como configuração, state e infraestrutura AWS se relacionam;
- compreender o ciclo completo antes de automatizá-lo.

Não haverá pipeline no `quadra-infra` nesta fase.

### Fase 2 — pacote coordenado de deploy da API

**Status: implementado na branch, aguardando merge e apply.** O pacote
usa exatamente duas branches e segue integralmente
`../../docs/planning-template.md` antes de qualquer implementação.

#### Branch do `quadra-api`

`feature/aws-api-deployment` reúne:

- interpretação segura de `DATABASE_SECRET`, preservando `DATABASE_URL` para o
  ambiente local;
- ajustes de runtime e migrations definidos pela spec;
- build e publicação de imagem imutável no ECR;
- criação ou seleção da nova revisão da task definition;
- atualização do ECS Service, rollback e verificação de saúde.

#### Branch do `quadra-infra`

`feature/aws-api-deployment-infrastructure` reúne:

- CI básico com `terraform fmt -check`, `init -backend=false` e `validate` em
  `pull_request` e `push` para `dev` e `main` (filtros de paths existentes),
  sem credenciais AWS, `plan` ou `apply`;
- integração GitHub OIDC;
- role dedicada e de menor privilégio para o deploy da API.

**Status: planejado, ainda não aplicado.** O workflow `.github/workflows/ci.yml` e
os recursos OIDC/IAM estão definidos no código desta branch, mas o provedor OIDC
e a role de deploy **não** devem ser tratados como provisionados até um
`terraform apply` manual confirmado pelo usuário.

O trust policy e as permissões exatas estão definidos na spec e materializados em
`terraform/github_oidc.tf` nesta branch, pendentes de apply, e ficarão
restritos ao repositório, referência e recursos necessários. Não serão usados
Access Keys permanentes, credenciais do usuário humano nem o profile local
`quadra-admin`.

#### Ordem de integração e ativação

```text
branches e PRs preparados separadamente
        ↓
branch do quadra-infra integrada
        ↓
plan novo → revisão → apply manual de OIDC/IAM
        ↓
JWT secret preenchido manualmente
        ↓
branch do quadra-api integrada em main
        ↓
CI existente
        ↓
build → ECR → revisão da task → ECS Service
        ↓
serviço estável + /health HTTP 200
```

A branch da API não deve ser integrada antes de OIDC, IAM e JWT estarem
prontos, pois o merge em `main` poderá disparar o primeiro deploy. O pacote
termina somente quando `https://api.appquadra.com.br` responder por uma task
saudável atrás do ALB.

#### Detalhes do pipeline aprovado (Tasks 5–6)

- o CI Terraform executa em `pull_request` e `push` para `dev` e `main`
  (com os filtros de paths existentes), somente `fmt -check`,
  `init -backend=false` e `validate`, sem credenciais AWS, `plan` ou `apply`;
- o workflow `CI/CD` da API usa OIDC restrito a
  `repo:matheusecke/quadra-api:ref:refs/heads/main`;
- a imagem usa o SHA completo e imutável; reruns reutilizam a mesma imagem;
- a action oficial registra a revision, executa `prisma migrate deploy` em task
  isolada, atualiza o Service para uma task e espera estabilidade;
- o circuit breaker faz rollback de deployments normais; o primeiro deploy é
  recuperado por novo commit/push, com scale-to-zero manual opcional;
- HTTP 200 em `https://api.appquadra.com.br/health` é a verificação final.

### Evolução opcional posterior — CI de infraestrutura com `terraform plan`

**Status: evolução opcional, ainda não implementada.** Só poderá ser considerada
depois da estabilização do CI básico e da autenticação GitHub → AWS.

Ao contrário do CI básico, essa fase exige acesso ao backend remoto, ao state do
Terraform e às APIs AWS. A autenticação deverá usar a identidade OIDC apropriada
e permissões separadas das usadas pelo deploy da API. O plan continuará sendo
apenas um artefato de revisão, nunca autorização para apply.

## CD da API

### Estado atual

```text
push / pull request
        ↓
GitHub Actions
        ↓
CI
```

O `quadra-api` possui CI para as verificações da aplicação, mas ainda não possui
CD para a AWS. ECR, RDS, ALB, task definition e ECS Service já estão
provisionados; o serviço permanece pausado com `desired_count = 0` porque ainda
faltam a compatibilidade com `DATABASE_SECRET`, o valor do JWT e a automação de
deploy.

### Estado futuro decidido

```text
merge / push main
        │
        ▼
CI
        │
        ├── install
        ├── tests
        └── build
        │
        ▼
CD
        │
        ├── autenticação AWS via OIDC
        ├── build Docker
        ├── push da imagem para ECR
        └── atualização do ECS Service
```

O Terraform já criou ECR, ECS Cluster, roles das tasks, RDS, ALB, task
definition e ECS Service. A identidade OIDC e a role de deploy da API estão
**planejadas** nesta branch e só passam a existir após `apply` confirmado. O
workflow `CI/CD` da API autentica via OIDC com trust restrito a
`repo:matheusecke/quadra-api:ref:refs/heads/main`, publica a imagem com tag do
SHA completo (reruns reutilizam o mesmo artefato), registra a revision da task,
executa `prisma migrate deploy` em task isolada, escala o Service para uma task,
aguarda estabilidade e valida HTTP 200 em
`https://api.appquadra.com.br/health`. Imagem e deploy de aplicação nunca
passarão por `terraform apply`. O circuit breaker do ECS faz rollback em
deployments normais; falha no primeiro deploy exige novo commit/push ou,
opcionalmente, scale-to-zero manual antes de nova tentativa.

## CD do frontend

### Estado atual

```text
push / pull request
        ↓
GitHub Actions
        ↓
CI
```

O `quadra-web` possui CI para as verificações da aplicação, mas ainda não possui
CD para a AWS.

### Estado futuro decidido

```text
merge / push main
        │
        ▼
CI
        │
        ├── install
        ├── tests/verificações existentes
        └── build
        │
        ▼
CD
        │
        ├── autenticação AWS via OIDC
        ├── build de produção
        ├── sync dos arquivos para S3
        └── invalidação do CloudFront
```

O Terraform criará e configurará o bucket S3, o CloudFront, o IAM necessário e
os recursos relacionados. O GitHub Actions publicará o conteúdo do frontend
nessa infraestrutura.

## Terraform CI versus Terraform CD

### CI de infraestrutura

Pode executar:

```text
terraform fmt -check
terraform init
terraform validate
terraform plan
```

Seu objetivo é verificar formatação e configuração, detectar erros, visualizar
alterações e permitir a revisão antes que elas sejam aplicadas. O `plan` apenas
descreve as mudanças propostas; ele não deve ser tratado como autorização para
alterar a AWS.

### CD de infraestrutura

Significa permitir que a automação execute:

```text
terraform apply
```

Esse comando pode alterar efetivamente a infraestrutura AWS, incluindo criar,
modificar, substituir ou remover recursos. Não há decisão de automatizar
imediatamente o `terraform apply`.

A abordagem inicial será:

```text
PR
↓
CI básico automático
↓
merge
↓
terraform plan manual atualizado
↓
review
↓
terraform apply manual
```

Assim, o projeto obtém os benefícios do CI mantendo controle humano explícito
sobre as alterações reais de infraestrutura. Automatizar o `plan` em pull
requests é opcional; mesmo sem essa automação, o `plan` manual deve ser revisado
antes de todo `apply`.

## Fase opcional futura — Terraform CD

**Status: evolução possível, não obrigatória para o TCC.**

```text
merge main
     ↓
GitHub Actions
     ↓
terraform apply
```

Essa automação somente deverá ser considerada depois que:

- o Terraform estiver estabilizado;
- remote state e locking estiverem consolidados;
- IAM e OIDC estiverem corretamente configurados;
- os processos de review estiverem definidos;
- o comportamento de `plan` e `apply` estiver bem compreendido.

## Identidades AWS

### Estado atual

```text
IAM user matheusecke
└── uso humano/local
```

### Evolução decidida

O GitHub Actions usará OIDC para assumir IAM roles de automação com credenciais
temporárias. Poderão existir identidades diferentes para:

- CI do Terraform;
- deploy da API;
- deploy do frontend.

Os nomes, a quantidade final de roles e suas permissões serão definidos durante
a implementação. Cada identidade deverá receber somente as permissões
necessárias à sua responsabilidade, seguindo least privilege.

Nenhuma automação dependerá de credenciais AWS permanentes armazenadas no
GitHub.

## Visão consolidada

```text
AGORA

quadra-api
└── CI

quadra-web
└── CI

quadra-infra
├── Terraform manual
└── infraestrutura da API provisionada
    └── ECS Service pausado


        ↓


PACOTE DE DEPLOY DA API — DUAS BRANCHES

quadra-api
└── feature/aws-api-deployment
    ├── runtime compatível com DATABASE_SECRET
    └── CI + CD → ECR → ECS


quadra-infra
└── feature/aws-api-deployment-infrastructure
    ├── CI: fmt + validate
    └── OIDC + role de deploy da API


        ↓


ORDEM DE ATIVAÇÃO

infra merge → plan revisado → apply manual
        ↓
JWT preenchido
        ↓
API merge → build → ECR → ECS → /health HTTP 200


        ↓


HOSPEDAGEM DO FRONTEND

quadra-web
└── CI atual; CD somente após S3 e CloudFront

quadra-infra
└── próxima etapa: frontend hosting
    └── S3 privado → CloudFront


        ↓


EVOLUÇÕES OPCIONAIS

quadra-infra
├── plan automático em PR
└── apply automatizado, se futuramente aprovado
```

## Princípios

1. Automação progressiva, não big bang.
2. Primeiro compreender manualmente, depois automatizar.
3. Terraform e deployment da aplicação têm responsabilidades diferentes.
4. CI de infraestrutura deve surgir antes de CD de infraestrutura.
5. `terraform plan` deve ser revisável.
6. `terraform apply` automatizado é opcional inicialmente.
7. GitHub Actions deve usar OIDC e credenciais temporárias.
8. Identidades humanas e de automação devem ser separadas.
9. Pipelines da API e do frontend passam a ter CD somente quando a
   infraestrutura necessária existir.
10. Nenhuma automação deve depender de credenciais AWS permanentes armazenadas
    no GitHub.
