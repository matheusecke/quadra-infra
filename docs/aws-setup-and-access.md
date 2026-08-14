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

- Nenhuma infraestrutura AWS da aplicação foi provisionada.
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
