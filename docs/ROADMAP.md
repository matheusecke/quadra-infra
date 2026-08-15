# Roadmap de infraestrutura

Decisões sobre provisionamento AWS e a abordagem de IaC deste projeto. O
backend remoto, a fundação de rede, a base da plataforma de containers, o banco
de dados, a zona DNS pública, o ALB e o ECS Service foram provisionados. O
serviço permanece pausado, sem tasks em execução, e o Docker Compose local
continua sendo o ambiente de desenvolvimento.
Ver o estado operacional em
[`aws-setup-and-access.md`](aws-setup-and-access.md).

## IaC: Terraform (decidido)

A infraestrutura AWS será provisionada e versionada com **Terraform**, neste repositório. Nada de console clicado à mão como fonte de verdade.

Recursos previstos:

| Recurso                        | Uso                                                            |
| ------------------------------ | -------------------------------------------------------------- |
| VPC (subnets, security groups) | rede base — desenho de saída em aberto, ver seção própria |
| RDS PostgreSQL                 | banco da aplicação                                           |
| ECR                            | registry privado da imagem `quadra-api`                       |
| ECS Fargate                    | execução da API                                              |
| ALB                            | entrada HTTPS da API                                           |
| S3                             | uploads e build estático do frontend                          |
| CloudFront                     | distribuição do frontend                                     |
| IAM                            | roles de task, deploy e SES                                    |
| CloudWatch                     | logs e métricas                                               |
| SES                            | envio de e-mail transacional (ver abaixo)                      |

**Contexto do projeto:** TCC acadêmico, sem usuários reais. As decisões abaixo otimizam custo e simplicidade de operação, não disponibilidade.

**Ambientes: um só.** Ver a seção *Ambiente único* abaixo.

**Relação com o GitHub Actions:** Terraform cuida só da infraestrutura (o que existe). O GitHub Actions cuida do ciclo da aplicação: build da imagem, push no ECR, `aws ecs update-service` para a API, e build + sync no S3/invalidação do CloudFront para o frontend. Deploy de aplicação não passa por `terraform apply`.

**Primeira implementação: simples.** Arquivos `.tf` planos na raiz de `terraform/`, state remoto em S3 com lock. Sem módulos próprios, sem camada de abstração, sem `terragrunt` — modularizar só quando houver o segundo ambiente pedindo reuso real.

> Status: backend remoto, locking, rede, Security Groups, ECR, ECS Cluster, IAM
> básico das tasks, CloudWatch Log Group, RDS, zona pública do Route 53, ALB,
> certificado, task definition e ECS Service provisionados. O serviço permanece
> com `desired_count = 0`, sem tasks em execução; o Docker Compose local segue
> sendo o ambiente de desenvolvimento.

## Evolução incremental da implementação

A infraestrutura será acrescentada em entregas pequenas e revisáveis. Cada
branch parte de `dev` atualizada e reúne recursos com a mesma responsabilidade.
Esses agrupamentos são unidades de trabalho, não módulos Terraform: o projeto
continua com um único root module e arquivos `.tf` planos em `terraform/`.

| Ordem | Branch sugerida | Escopo principal |
| --- | --- | --- |
| 1 | `feature/terraform-network` | nomes e tags comuns, VPC, subnets públicas e privadas, Internet Gateway e rotas públicas, sem NAT Gateway |
| 2 | `feature/terraform-security-groups` | security groups do ALB, ECS e RDS e suas relações de acesso |
| 3 | `feature/terraform-container-platform` | ECR, ECS Cluster, IAM básico da task e logs no CloudWatch |
| 4 | `feature/terraform-database` | DB subnet group, RDS PostgreSQL e estratégia de credenciais |
| 5 | `feature/terraform-api-service` | ALB, target group, listener, task definition e ECS Service da API |
| 6 | `feature/terraform-frontend-hosting` | bucket privado do frontend, CloudFront e acesso entre eles |
| 7 | `feature/terraform-app-storage` | bucket de uploads da aplicação e permissões necessárias |
| 8 | `feature/terraform-operations` | mecanismo de pausa e retomada e scheduler do RDS |
| 9 | `ci/terraform-validation` | CI básico com `fmt -check`, `init` e `validate`, sem alterar a AWS |
| 10 | `feature/github-oidc` | autenticação GitHub Actions → AWS e roles de automação |
| 11 | `ci/terraform-plan` | evolução **opcional** para apresentar o `plan` nos pull requests |
| 12 | `feature/terraform-email` | SES e permissões de envio; entrega **opcional e última** |

> Etapa 1 concluída: `feature/terraform-network` provisionou a VPC, duas subnets
> públicas, duas privadas, Internet Gateway e route tables, sem NAT Gateway.

> Etapas 2 e 3 concluídas: os Security Groups foram provisionados e
> `feature/terraform-container-platform` criou o ECR compartilhado da API, o ECS
> Cluster, as roles de execução e da aplicação e o log group da API.

> Etapa 4 concluída: `feature/terraform-database` provisionou o DB subnet group
> e o RDS PostgreSQL privado. A zona pública `appquadra.com.br` foi criada no
> Route 53 no início da etapa 5 e delegada pelo Registro.br.

> Etapa 5 provisionada: ALB, certificado ACM, registros DNS, target group, task
> definition, IAM adicional e ECS Service foram criados. O serviço permanece
> pausado até a publicação da primeira imagem compatível da API.

Os arquivos Terraform serão separados por responsabilidade apenas quando cada
entrega precisar deles, por exemplo: `locals.tf`, `network.tf`,
`security_groups.tf`, `ecr.tf`, `database.tf`, `ecs.tf`, `alb.tf`,
`frontend.tf`, `storage.tf`, `operations.tf` e `ses.tf`. Não serão criados
arquivos vazios ou abstrações antecipadas.

O `terraform plan` automatizado no CI é opcional. Independentemente de sua
adoção, todo `terraform apply` manual continuará exigindo um `plan` atualizado
e revisado. Os CDs da API e do frontend serão implementados nos respectivos
repositórios quando as dependências AWS de cada aplicação existirem.

O escopo do ECR foi confirmado na terceira entrega: existe um único repositório
privado compartilhado, `quadra-api`, para a imagem Docker da API. O frontend
continuará como build estático publicado em S3, sem imagem própria no ECR.

## Ambiente único (decidido)

Começa com **um único ambiente AWS**, tratado como `production` — ou `demo`, que descreve melhor o uso real: é o ambiente que existe para demonstrar e defender o TCC. Não haverá `staging` agora.

**Fluxo inicial:**

```text
desenvolvimento local (Docker Compose)
        │
        ▼
   push / merge na main
        │
        ▼
    GitHub Actions  ──build da imagem──▶ ECR
        │
        ▼
  deploy no ambiente AWS único
```

O Docker Compose local **continua exatamente como está** — é o ambiente de desenvolvimento e não muda por causa disso.

**Staging fica para depois**, e só acontece se houver tempo, interesse e orçamento sobrando no fim do projeto. Um segundo ambiente dobra o custo fixo (outro RDS, outro ALB, outro serviço ECS) e é justamente o custo fixo que as decisões deste documento estão tentando conter.

**Evolução possível, explicitamente fora do escopo inicial:**

```text
dev  → staging
main → production
```

### O que isso exige do Terraform desde já

Nada de estrutura extra — só disciplina de nomes, para que acrescentar um segundo ambiente depois não vire reescrita:

- **uma variável `environment`** (valor inicial `production`) e um `local` de prefixo derivado dela, usado no nome e nas tags de todo recurso: `tcc-${var.environment}-api`, `tcc-${var.environment}-db`. Nunca nomes literais no meio do código;
- **nada de nome acoplado a um mundo de dois ambientes** — nem `tcc-prod-*` escrito à mão, nem sufixos que só fazem sentido quando existe um par. O prefixo sai da variável, ponto;
- **atenção aos nomes globalmente únicos** (bucket S3, repositório ECR, zona/registros DNS): são os que quebram na hora de duplicar, então já nascem derivados do prefixo;
- **ECR e o bucket de state são compartilhados** entre ambientes futuros, não duplicados — a imagem publicada é o mesmo artefato, e o state comporta mais de um ambiente. Esses ficam fora do prefixo de propósito;
- **sem workspaces, sem diretório por ambiente, sem módulos** agora. Quando o segundo ambiente existir, ele é um `terraform.tfvars` diferente — e aí sim se avalia workspace ou diretório, com o problema real na frente.

## Região AWS: `us-east-1` (decidido por comparação de preço)

O critério foi: **a região mais barata que ofereça todos os serviços do projeto** — VPC, RDS PostgreSQL, ECS Fargate, ALB, ECR, S3 e CloudFront. `us-east-1` entrou como referência de comparação, não como escolha automática, e venceu a comparação.

Ordem de grandeza dos itens que pesam (on-demand, confirmar na calculadora da AWS antes de provisionar):

| Item                                     | `us-east-1`                 | `sa-east-1` (São Paulo) |
| ---------------------------------------- | ----------------------------- | -------------------------- |
| Fargate 0,25 vCPU + 0,5 GB               | ~US$ 9/mês | ~US$ 13/mês  |                            |
| RDS`db.t4g.micro` single-AZ            | ~US$ 12/mês | ~US$ 19/mês |                            |
| ALB (hora-base, sem LCU)                 | ~US$ 16/mês | ~US$ 23/mês |                            |
| S3, ECR, CloudFront no volume do projeto | centavos                      | centavos                   |

`sa-east-1` fica na faixa de 40-60% mais caro em todos os itens de computação e rede. A vantagem que ela teria é latência (~120 ms a menos a partir do Brasil), irrelevante para uso de demonstração e apresentação — não compensa a diferença de conta.

Duas observações que valem independentemente da escolha:

- **CloudFront** não é cobrado pela região do stack e sim por localização de borda / price class — é neutro nessa comparação;
- **certificado ACM usado pelo CloudFront precisa estar em `us-east-1`** de qualquer forma. Aqui isso deixa de ser complicação, já que é a região do stack inteiro.

## Banco de dados: PostgreSQL privado e de baixo custo (decidido)

O banco da aplicação será uma instância RDS PostgreSQL `16.14`, compatível com o
major 16 usado no desenvolvimento local. A configuração prioriza baixo custo e
proteção dos dados para o ambiente único de demonstração:

- classe `db.t4g.micro`, Single-AZ, sem Availability Zone fixada;
- armazenamento gp3 criptografado, começando em 20 GiB e com autoscaling
  limitado a 50 GiB;
- DB subnet group `quadra-production-db-subnet-group`, formado pelas duas
  subnets privadas;
- endpoint sem exposição pública, porta `5432` e acesso somente pelo Security
  Group das tasks ECS;
- banco lógico `quadra` e usuário administrativo `quadra_admin`;
- senha master gerada pelo RDS e armazenada no Secrets Manager com as chaves
  gerenciadas pela AWS, sem senha no HCL ou no state;
- backups automáticos por 1 dia na janela `06:00-06:30` UTC e snapshot final
  obrigatório em uma eventual exclusão. A retenção reduzida respeita a limitação
  do AWS Free Plan atual e pode ser ampliada após a migração para o plano pago;
- janela de manutenção aos domingos entre `07:00-08:00` UTC, com alterações
  disruptivas adiadas para essa janela;
- atualizações menores automáticas, atualização principal bloqueada e adesão
  ao RDS Extended Support desabilitada para evitar cobrança futura silenciosa;
- Database Insights Standard com 7 dias de histórico, sem Enhanced Monitoring,
  exportação contínua de logs ou autenticação IAM nesta fase;
- deletion protection nativa do RDS, sem duplicação com
  `lifecycle.prevent_destroy`.

O usuário administrativo não é o usuário da conta root AWS e também não recebe
acesso irrestrito ao sistema operacional do RDS. Um usuário PostgreSQL específico
para a aplicação, com menor privilégio, será criado quando o processo real de
migrations estiver definido. A futura task definition consumirá o secret sem
gravar a senha diretamente no Terraform.

O custo recorrente principal é a instância, estimada em cerca de US$ 12/mês em
`us-east-1`, além do armazenamento, do secret e de eventuais backups que excedam
a franquia. Database Insights Standard, DB subnet group e deletion protection
não acrescentam custo direto. Snapshots preservados e o crescimento automático
do volume continuam sendo cobrados.

## API pública: HTTPS no ALB e serviço ECS inicialmente pausado (provisionado)

A API usa `https://api.appquadra.com.br`; o domínio raiz permanece reservado
para o frontend. A zona pública `appquadra.com.br` é gerenciada pelo Route 53 e
os quatro name servers da AWS foram delegados no Registro.br. A configuração da
API acrescentou:

- certificado ACM específico para `api.appquadra.com.br`, validado por registro
  DNS criado pelo Terraform;
- ALB público nas duas subnets públicas, com deletion protection habilitada;
- listener HTTP na porta 80 apenas para redirecionamento permanente para HTTPS;
- listener HTTPS na porta 443 com a policy
  `ELBSecurityPolicy-TLS13-1-2-2021-06`, encaminhando ao target group HTTP na
  porta `3001`;
- alias `A` no Route 53 apontando `api.appquadra.com.br` para o ALB;
- target group do tipo `ip`, deregistration delay de 30 segundos e health check
  em `/health`: intervalo 30 s, timeout 5 s, dois sucessos para saudável, três
  falhas para não saudável e resposta esperada `200`.

Somente HTTPS será usado pela aplicação. Manter a porta 80 para redirecionar é
uma prática comum e não transmite conteúdo da API em HTTP: o ALB responde com o
redirecionamento antes de encaminhar qualquer requisição ao container. O
certificado ACM público não tem custo adicional, enquanto o ALB permanece
cobrado continuamente, estimado em cerca de US$ 16/mês mais LCUs, mesmo com o
serviço pausado. Access logs do ALB e WAF ficam fora desta fase; devem ser
reavaliados antes de receber usuários reais ou quando houver requisito de
auditoria.

A task definition da API usa Fargate on-demand, Linux `X86_64`, `0.25` vCPU e
`0.5` GiB, com container `api` na porta `3001`. O processo init do runtime é
habilitado para tratar corretamente processos filhos. A task permanece nas
subnets públicas com IP público, conforme a decisão sem NAT, e recebe tráfego na
porta da API apenas do Security Group do ALB.

O ECS Service nasce com `desired_count = 0`: a infraestrutura pode ser criada
antes de existir uma imagem válida e não gera custo de task Fargate. A referência
inicial usa a tag `bootstrap` do ECR apenas para tornar a task definition válida;
ela não será executada nessa condição. Depois que o CI publicar a primeira
imagem, o GitHub Actions registrará ou selecionará a revisão real e alterará a
quantidade desejada. Por isso o Terraform ignora mudanças em `desired_count` e
`task_definition`: esses dois campos pertencem ao ciclo de deploy da aplicação,
enquanto a estrutura da task continua declarada no Terraform. Alterar CPU,
memória, secrets ou variáveis cria uma nova revisão, mas o CI ainda precisa
mandar o serviço adotar essa revisão.

O deploy usa mínimo saudável de 100%, máximo de 200%, grace period de health
check de 60 segundos e circuit breaker com rollback. ECS Exec fica habilitado
para diagnóstico sem abrir portas; a task role recebe somente as quatro ações
`ssmmessages` necessárias, com `Resource = "*"` porque essas ações não oferecem
escopo útil por ARN. O filesystem não é somente leitura porque o agente do ECS
Exec precisa escrever durante a sessão.

As variáveis não sensíveis da task são apenas `PORT=3001` e
`CORS_ORIGIN=https://appquadra.com.br`. Localhost não é aceito pela API real: o
frontend local continua usando a API local, evitando acesso acidental aos dados
do ambiente AWS e incompatibilidade com o cookie de refresh `SameSite=Strict`.

Os secrets seguem responsabilidades separadas:

- o secret master do RDS, já gerado e preenchido pelo serviço, será injetado
  integralmente como `DATABASE_SECRET`;
- o Terraform cria somente o secret vazio
  `quadra-production-api-jwt-secret`, com retenção de sete dias e
  `prevent_destroy`; seu valor aleatório deve ser inserido manualmente antes da
  primeira task ser executada;
- o Terraform não lê nem grava os valores dos secrets, portanto eles não entram
  no HCL nem no state;
- a execution role recebe `secretsmanager:GetSecretValue` somente para esses
  dois ARNs. A task role não recebe acesso aos secrets, pois a resolução ocorre
  antes da inicialização do container.

Antes do primeiro deploy, a API precisa aceitar `DATABASE_SECRET` no formato
JSON produzido pelo RDS e construir internamente a conexão PostgreSQL, mantendo
`DATABASE_URL` para desenvolvimento local. Sem essa compatibilidade e sem o
valor do JWT secret, o serviço deve continuar com `desired_count = 0`.

## Desenho de rede: sem NAT Gateway (decisão implementada)

A task Fargate precisa de **saída** para a internet — ela baixa a imagem do ECR antes de o container subir, e depois chama SES e CloudWatch. Ela não precisa de **entrada**: quem fala com ela é só o ALB. Existem duas formas de dar essa saída, e elas diferem em custo e em profundidade de defesa.

### Opção A — task em subnet privada + NAT Gateway

Subnets públicas para o ALB, subnets privadas para a task, um NAT Gateway na subnet pública com IP elástico, e a rota da subnet privada apontando para ele. A task sai pelo NAT; de fora, ninguém consegue endereçá-la porque **não existe rota até ela**.

- **Vantagem:** a proteção não depende de configuração. Errar o security group — anexar o do ALB à task, abrir a porta para `0.0.0.0/0` num debug — não expõe nada.
- **Vantagem:** passa limpo em verificação automática de boas práticas (Security Hub, CIS).
- **Desvantagem:** ~US$ 33/mês fixos (US$ 0,045/h) + US$ 0,045/GB, cobrados 24h por dia, **inclusive com o ambiente pausado** — NAT não pausa. Ambiente pausado sai ~US$ 51/mês.
- **Desvantagem:** o desenho tecnicamente correto teria um NAT por zona de disponibilidade (~US$ 66/mês); com um só, a queda daquela zona deixa a task da outra sem saída.

### Opção B — task em subnet pública com IP público

Task e ALB nas subnets públicas, `assign_public_ip = true`, sem NAT e sem IP elástico. A task sai direto pelo Internet Gateway. A entrada continua sendo só pelo ALB: o security group da task tem uma única regra, porta da API com origem **o security group do ALB** (não um bloco de IPs), e security group nega o resto por padrão.

- **Vantagem:** US$ 0 de rede. Ambiente pausado sai ~US$ 18/mês, contra ~US$ 51 da opção A — ~US$ 265 de diferença ao longo do TCC.
- **Vantagem:** um recurso a menos para provisionar, entender e manter.
- **Desvantagem:** a task tem endereço na internet. A única coisa que a protege é o security group, então um erro de configuração futuro expõe a API na hora, sem ALB na frente.
- **Desvantagem:** torna fácil o atalho perigoso de "abrir uma porta só um minutinho" — em subnet pública, abrir é abrir para o mundo.
- **Desvantagem:** `assign_public_ip = true` é marcado como achado em checklist automático de segurança.

### O que não muda entre as duas

O **RDS fica em subnet privada nos dois desenhos**, sem IP público, aceitando conexão apenas do security group da task. O ativo que importa — os dados — tem a mesma proteção de qualquer forma. Nenhuma das opções coloca o banco na internet.

Vale registrar também o que o NAT **não** resolve: ele não protege contra a aplicação comprometida. Uma falha de execução remota na API já está do lado de dentro, alcança o banco igual e tem saída para a internet pelo próprio NAT. O NAT protege contra alguém **chegar** na task, não contra alguém que já esteja nela.

### Comparação

|                                     | A: privada + NAT              | B: pública + IP público              |
| ----------------------------------- | ----------------------------- | -------------------------------------- |
| Entrada pelo ALB                    | igual                         | igual                                  |
| Task endereçável de fora          | impossível                   | possível, barrada pelo security group |
| Erro de security group expõe a API | não                          | sim                                    |
| Proteção do RDS                   | idêntica                     | idêntica                              |
| Defesa contra app comprometida      | nenhuma                       | nenhuma                                |
| Custo fixo de rede                  | ~US$ 33/mês | US$ 0        |                                        |
| Ambiente pausado                    | ~US$ 51/mês | ~US$ 18/mês |                                        |

### Decisão implementada: **sem NAT** (opção B)

**Tecnicamente, a opção A é a melhor.** Subnet privada com NAT é o desenho que se recomendaria para qualquer sistema com usuários reais, e a única razão de não adotá-lo aqui é custo — não é que o NAT tenha sido considerado desnecessário.

A escolha se justifica pelo contexto registrado no topo deste documento: TCC acadêmico, sem usuários reais, sem dados de terceiros, ambiente único, ligado apenas durante desenvolvimento e apresentação. Nesse cenário, os ~US$ 33/mês compram proteção contra **um erro de configuração cometido por mim mesmo no futuro**, num ambiente onde o Terraform é o único caminho de mudança e o banco continua isolado de qualquer jeito.

**Os riscos estão entendidos e aceitos conscientemente:**

1. a segurança da task passa a depender inteiramente de um security group escrito corretamente;
2. um erro nesse security group expõe a API diretamente, sem o ALB na frente;
3. o desenho não passa em checklist automático de boas práticas, e essa escolha precisa ser justificada em vez de simplesmente cumprida.

**Mitigações que custam zero e devem ser seguidas:** a regra de entrada da task referencia o *security group* do ALB, nunca um bloco de IPs; nenhuma alteração de rede fora do Terraform; nenhuma porta aberta "temporariamente" — se precisar de acesso ao container, usar `ecs execute-command`, que funciona sem abrir porta nenhuma.

**Quando reverter para A:** se o ambiente passar a receber usuários reais, dados de terceiros ou qualquer coisa que não seja demonstração acadêmica. A migração é barata (mover a task para as subnets privadas, criar o NAT, ajustar a rota) e não destrói nada — mais um motivo para não pagar por ela antes da hora.

## Ciclo de vida: pausar, não destruir

**`terraform destroy` não faz parte do fluxo normal.** A infraestrutura é criada uma vez e mantida; nada de destruir e recriar entre sessões de uso. Recriar significa endpoint de banco novo, DNS novo, certificado novo e dados perdidos — custo de operação alto para economizar pouco.

No lugar disso, existe um **mecanismo de pausa** para quando o ambiente não estiver em uso.

| Ação                                                               | Pausar                | Retomar               |
| -------------------------------------------------------------------- | --------------------- | --------------------- |
| ECS service                                                          | `desired_count = 0` | `desired_count = 1` |
| RDS                                                                  | instância parada     | instância iniciada   |
| ALB, NAT Gateway (se existir), IPs, S3, ECR, DNS, state do Terraform | permanecem            | permanecem            |

Na retomada a ordem importa: **primeiro o RDS**, esperar ficar disponível, **depois** subir o ECS — e só considerar o ambiente utilizável **após o health check do target group passar**. A API não sobe saudável contra um banco que ainda está iniciando.

### Pausar reduz o custo, não zera

Com o ambiente pausado continuam gerando cobrança, entre outros: **ALB** (custo por hora + LCU), **NAT Gateway e IPs elásticos** caso o desenho com NAT seja adotado (custo por hora + dados), **armazenamento do RDS e seus backups/snapshots**, **S3**, **ECR** e logs retidos no CloudWatch. A pausa corta o que é computação (tarefas Fargate e horas de instância do RDS), e é isso.

### Limitação da AWS: RDS parado volta sozinho em 7 dias

Uma instância RDS parada:

- **continua cobrando armazenamento e backups** normalmente;
- **é reiniciada automaticamente pela AWS após 7 dias**, e passa a cobrar horas de instância de novo até ser parada outra vez.

Ou seja, a pausa de RDS é uma pausa **de até uma semana**, não indefinida. Um ambiente esquecido pausado volta a custar sozinho.

**Tratamento decidido:** uma regra diária do **EventBridge Scheduler** chamando `rds:StopDBInstance` direto como target universal — sem Lambda, poucas linhas de Terraform. Se a AWS religar a instância no sétimo dia, ela cai de novo no dia seguinte. A regra não atrapalha o uso normal: quando o ambiente está retomado de propósito, basta desabilitá-la ou reagendá-la para fora do horário de uso.

### Como isso será implementado (a definir)

Nada disso é código ainda. As formas possíveis, da mais simples para a mais elaborada:

1. **Script de operação com AWS CLI** (`pause.sh` / `resume.sh`) chamando `aws ecs update-service`, `aws rds stop-db-instance` / `start-db-instance`, com `aws rds wait` e `aws ecs wait services-stable` para a espera de health check;
2. **Workflow manual no GitHub Actions** (`workflow_dispatch`) executando esses mesmos comandos, para não depender de credencial na máquina local;
3. **Terraform** para a parte que é declarativa — nota importante: `terraform apply` sabe zerar o `desired_count` do ECS, mas **não sabe parar um RDS** (o recurso não expressa esse estado). Então o mecanismo não pode ser só Terraform. E se o `desired_count` for controlado por fora, o recurso ECS precisa de `lifecycle { ignore_changes = [desired_count] }` para um apply não despausar o ambiente sem querer.

## E-mail transacional (esqueci minha senha)

**Status: evolução opcional e última da sequência de implementação.** O fluxo
de recuperação de senha ainda precisa ser implementado de forma coordenada no
`quadra-api` e no `quadra-web`; a infraestrutura de e-mail só será criada
quando essa funcionalidade entrar no escopo.

**Decisão: Amazon SES chamado direto pela API NestJS** (`@aws-sdk/client-sesv2`, `SendEmail`). Sem Lambda.

Por quê: o envio é uma chamada HTTPS dentro do request de `POST /auth/forgot-password`. Uma Lambda no meio só acrescentaria uma função, um deploy e um IAM a mais para fazer a mesma chamada. Lambda/SQS só se passar a existir necessidade de retry assíncrono ou volume — não é o caso.

O que o Terraform provisiona: identidade de domínio verificada + registros DKIM, e a policy `ses:SendEmail` na task role do ECS. Credencial nenhuma no `.env` — em Fargate o SDK pega a role da task.

Pegadinha real: SES começa em **sandbox** (só destinatários verificados, 200 e-mails/dia). Sair da sandbox exige pedido de acesso de produção à AWS (~24h, pode ser negado). Pedir cedo.

Plano B se a AWS travar a saída da sandbox: **Resend** (free tier 3k e-mails/mês, sem análise prévia). É trocar o cliente de envio — o fluxo de token de reset no `quadra-api` não muda.
