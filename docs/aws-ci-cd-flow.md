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
  e, depois, também apresenta o `terraform plan` para revisão.

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

### Fase 2 — CI básico do `quadra-infra`

**Status: próxima etapa decidida, ainda não implementada.**

O primeiro workflow de infraestrutura será criado depois que:

- existir uma estrutura Terraform real;
- o backend remoto estiver funcionando;
- `.terraform.lock.hcl` estiver presente;
- os primeiros recursos estiverem estabilizados.

O workflow será exclusivamente de validação:

```text
Pull Request
      │
      ▼
GitHub Actions
      │
      ├── terraform fmt -check
      ├── terraform init
      └── terraform validate
```

Essa etapa não executará `terraform apply`, não modificará recursos AWS e não
automatizará o provisionamento. Conceitualmente, ela terá o mesmo papel dos CIs
já existentes na API e no frontend: validar o código antes do merge.

### Fase 3 — CI de infraestrutura com `terraform plan`

**Status: etapa decidida para depois da estabilização do CI básico e da
autenticação GitHub → AWS.**

```text
Pull Request
      │
      ▼
terraform fmt -check
      │
terraform init
      │
terraform validate
      │
terraform plan
      │
      ▼
revisão das mudanças propostas
```

Ao contrário do CI básico, essa fase exige acesso ao backend remoto, ao state do
Terraform e às APIs AWS. A autenticação deverá usar credenciais temporárias:

```text
GitHub Actions
      ↓
GitHub OIDC
      ↓
AWS STS
      ↓
IAM Role
      ↓
AWS
```

Não serão usados na automação:

- Access Key permanente;
- Secret Access Key permanente;
- credenciais do usuário `matheusecke`;
- profile local `quadra-admin`.

A identidade humana usada localmente e as identidades de automação permanecerão
separadas:

```text
Desenvolvimento local

matheusecke
    ↓
aws login
    ↓
quadra-admin
    ↓
AWS


Automação

GitHub Actions
    ↓
GitHub OIDC
    ↓
AWS STS
    ↓
IAM Role
    ↓
AWS
```

### Fase 4 — infraestrutura da aplicação disponível

**Status: etapa futura decidida, dependente dos recursos necessários.**

À medida que o Terraform provisionar ECR, ECS, RDS, ALB, S3, CloudFront, IAM e
os demais componentes, passará a existir infraestrutura suficiente para o CD
das aplicações.

Essa fase não depende da conclusão de toda a infraestrutura. O CD de cada
repositório pode ser introduzido assim que suas próprias dependências estiverem
disponíveis e estabilizadas.

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
CD para a AWS.

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

O Terraform criará ECR, ECS Cluster, ECS Service, IAM Roles e os recursos
relacionados. O GitHub Actions publicará uma nova versão da API nessa
infraestrutura. Uma nova imagem não será publicada por meio de
`terraform apply`.

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
CI automático
↓
terraform plan
↓
review
↓
merge
↓
terraform apply manual
```

Assim, o projeto obtém os benefícios do CI mantendo controle humano explícito
sobre as alterações reais de infraestrutura.

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
└── Terraform manual


        ↓


PRÓXIMA EVOLUÇÃO

quadra-api
└── CI

quadra-web
└── CI

quadra-infra
└── CI
    ├── fmt
    └── validate


        ↓


DEPOIS

quadra-infra
└── CI
    ├── fmt
    ├── validate
    └── plan

GitHub
└── OIDC → AWS


        ↓


INFRA DISPONÍVEL

quadra-api
└── CI + CD
    └── ECR → ECS

quadra-web
└── CI + CD
    └── S3 → CloudFront

quadra-infra
└── CI + plan
    └── apply manual


        ↓


OPCIONAL FUTURO

quadra-infra
└── CI + CD
    └── apply automatizado
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
