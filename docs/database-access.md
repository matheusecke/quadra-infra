# Acesso ao banco de dados

Procedimento para conectar ao RDS PostgreSQL de produção e executar comandos ou
scripts SQL manualmente. Validado em 16/08/2026.

O banco não é acessível pela internet: fica em subnets sem rota para o internet
gateway e o security group aceita a porta `5432` apenas a partir do security
group das tasks ECS. Não existe bastion, VPN ou túnel.

O único caminho confirmado é o **AWS CloudShell em modo VPC**, que cria um
terminal dentro da própria VPC. Escolhendo o security group das tasks ECS, a
regra de entrada já provisionada autoriza a conexão — **nenhuma alteração de
infraestrutura é necessária**, e nada fica exposto.

## Antes de começar: a credencial

O usuário master é `quadra_admin` e a senha é gerada e mantida pelo RDS
(`manage_master_user_password`). Ela não existe em nenhum arquivo do
repositório.

Onde obter, pelo console:

1. RDS → **Databases** → `quadra-production-db`
2. Aba **Configuration**, campo *Master Credentials ARN*
3. **Manage in Secrets Manager** → **Retrieve secret value**
4. Copiar o campo `password`

**Obtenha a senha antes de entrar no ambiente.** Ambientes VPC não têm acesso à
API da AWS (ver [Limitações](#limitações-do-ambiente)), então não é possível
consultar o Secrets Manager de dentro do terminal.

Copie no momento do uso. Não salve em arquivo, não cole em documento e não
versione: é a única credencial administrativa do banco e a AWS pode rotacioná-la.

## Criando o ambiente

No console, abra o CloudShell pelo ícone `>_` no canto superior direito, e então
**Actions** → **Create VPC environment**:

| Campo          | Valor                                                                                  |
| -------------- | -------------------------------------------------------------------------------------- |
| VPC            | `vpc-0cfb1beb1d75d1142`                                                              |
| Subnet         | `subnet-0d614b2a1969257b7` (`quadra-production-private-a`, mesma AZ da instância) |
| Security group | `sg-061558ae133a81fc0` (`quadra-production-ecs-sg`)                                |

O security group é a única escolha que importa. Use o **das tasks ECS**, não o
do próprio banco: o security group do RDS não tem nenhuma regra de saída — é
intencional, o banco não inicia conexões — e um ambiente criado com ele fica
mudo, resultando em `Connection timed out`.

Atenção ao atalho **Connect using CloudShell**, oferecido na tela da instância
RDS: ele preenche a configuração de rede copiando a da instância, inclusive o
security group do banco, que é exatamente o que não funciona. Troque o security
group manualmente antes de confirmar.

O ambiente é criado pelo console e **não é gerenciado por Terraform**. Apagá-lo
e recriá-lo não gera divergência de estado.

## Conectando

```bash
psql 'host=quadra-production-db.c4t06g4a8t85.us-east-1.rds.amazonaws.com port=5432 user=quadra_admin dbname=quadra sslrootcert=/certs/global-bundle.pem sslmode=verify-full'
```

A senha é solicitada por prompt. O bundle de autoridades certificadoras do RDS
já vem no ambiente, em `/certs/global-bundle.pem`, o que permite usar
`sslmode=verify-full` — a conexão é cifrada **e** a cadeia do certificado é
validada.

O parâmetro `rds.force_ssl` está em `1` no parameter group `default.postgres16`,
portanto conexões sem TLS são recusadas pelo servidor.

Saída esperada:

```
psql (16.14)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

quadra=>
```

## Limitações do ambiente

- **Armazenamento efêmero.** O `$HOME` é apagado ao fim da sessão. Todo arquivo
  precisa ser recriado na sessão seguinte.
- **Expira por inatividade**, em torno de 20 a 30 minutos.
- **Sem acesso à internet e à API da AWS.** Ambientes VPC não recebem IP
  público, então nem em subnet pública há saída. `aws sts`, `aws secretsmanager`
  e `aws s3` falham com timeout.
- **Sem upload e download pela interface.** As opções do menu *Actions* não
  funcionam em ambientes VPC.
- **Máximo de dois ambientes VPC** por usuário IAM.
- **Security group não é editável** depois da criação: para trocar, é preciso
  apagar o ambiente e criar outro.

A configuração do ambiente (nome, VPC, subnet, security groups) permanece salva
e pode ser reaberta; apenas o conteúdo do disco é perdido.

## Guia do `psql`

### SQL puro é o padrão

O `psql` é apenas um terminal ligado ao banco. **Tudo que você digita é SQL
normal** — não existe uma linguagem própria a aprender:

```sql
SELECT id, name, slug FROM organizations WHERE is_deleted = false;
```

Duas regras, e são as únicas:

1. **O comando só executa quando encontra o `;`.** Sem ponto e vírgula, o
   `psql` continua esperando você digitar. Isso é proposital: permite quebrar
   uma consulta em várias linhas.
2. **Linhas iniciadas por `\` não são SQL.** São meta-comandos do próprio
   `psql` (`\dt`, `\x`, `\q`), e esses não levam `;`.

Tudo que funciona em SQL funciona aqui: `SELECT`, `INSERT`, `UPDATE`, `DELETE`,
`CREATE TABLE`, `ALTER TABLE`, `BEGIN`/`COMMIT`, CTEs, funções, `EXPLAIN`.

### O prompt indica o estado

Prestar atenção nele evita a maior parte da confusão:

| Prompt       | Significado                                                    |
| ------------ | -------------------------------------------------------------- |
| `quadra=>` | Pronto para um novo comando                                    |
| `quadra->` | Comando incompleto — falta o`;`                             |
| `quadra(>` | Há um parêntese aberto                                       |
| `quadra'>` | Há uma aspa simples aberta                                    |
| `quadra*>` | Há uma transação aberta, faltando`COMMIT` ou `ROLLBACK` |
| `quadra!>` | Transação abortada: tudo é ignorado até um`ROLLBACK`     |

Travou em `->`, `(>` ou `'>` por causa de um erro de digitação? `Ctrl+C`
descarta a linha e devolve o prompt limpo, sem fechar a sessão.

### Resultados abrem em um paginador

Consultas com muitas linhas não são impressas direto na tela: abrem no `less`.
Navegue com as setas ou `PgUp`/`PgDn` e **saia com `q`**. Sem saber disso, a
sensação é de terminal travado.

Para desligar o paginador e deixar tudo rolar na tela:

```
\pset pager off
```

### Meta-comandos são atalhos para SQL

Todo `\d...` é apenas uma consulta pronta ao catálogo do PostgreSQL. São mais
curtos, mas o SQL equivalente sempre existe — e é o que se usa dentro de um
script, onde meta-comandos não são adequados.

| Meta-comando  | O que faz                                | Equivalente em SQL                                                                                                                   |
| ------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `\dt`       | Lista as tabelas                         | `SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY 1;`                                       |
| `\d users`  | Descreve colunas, índices e constraints | `SELECT column_name, data_type, is_nullable FROM information_schema.columns WHERE table_name = 'users' ORDER BY ordinal_position;` |
| `\di`       | Lista os índices                        | `SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public';`                                                          |
| `\dT+`      | Lista os tipos, incluindo enums          | `SELECT t.typname, e.enumlabel FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid ORDER BY 1, e.enumsortorder;`                  |
| `\dn`       | Lista os schemas                         | `SELECT schema_name FROM information_schema.schemata;`                                                                             |
| `\l`        | Lista os bancos                          | `SELECT datname FROM pg_database;`                                                                                                 |
| `\du`       | Lista os usuários                       | `SELECT rolname FROM pg_roles;`                                                                                                    |
| `\conninfo` | Host, porta, usuário e cifra em uso     | —                                                                                                                                   |

As constraints `CHECK`, que o Prisma não declara no schema e são escritas à mão
nas migrations, aparecem em:

```sql
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'organization_user_affiliations'::regclass;
```

E as migrations já aplicadas:

```sql
SELECT migration_name, finished_at
FROM _prisma_migrations
ORDER BY finished_at;
```

### Consultando os dados

**Toda tabela usa soft delete.** Filtrar `is_deleted = false` é necessário em
praticamente qualquer consulta útil; sem isso você vê registros já apagados
logicamente.

```sql
SELECT id, name, slug, status
FROM organizations
WHERE is_deleted = false
ORDER BY id;
```

```sql
SELECT u.id, u.email, u.name, a.role, t.name AS team
FROM users u
JOIN organization_user_affiliations a ON a.user_id = u.id
LEFT JOIN teams t ON t.id = a.team_id
WHERE u.is_deleted = false
  AND a.is_deleted = false
  AND a.organization_id = 1
ORDER BY a.role, u.name;
```

```sql
SELECT role, count(*)
FROM organization_user_affiliations
WHERE is_deleted = false AND status = 'ACTIVE'
GROUP BY role;
```

Valores de enum são comparados como texto entre aspas simples: `'ACTIVE'`,
`'ORG_ADMIN'`, `'PG'`.

### Alterando dados com segurança

Por padrão **cada comando é confirmado imediatamente** — um `UPDATE` sem
`WHERE` não tem desfazer. Envolva alterações em uma transação:

```sql
BEGIN;

UPDATE users SET name = 'Nome Corrigido' WHERE id = 42;

SELECT id, email, name FROM users WHERE id = 42;
```

O prompt vira `quadra*>`. Se o resultado estiver certo:

```sql
COMMIT;
```

Se não:

```sql
ROLLBACK;
```

Dois hábitos que evitam a maioria dos acidentes:

1. Rodar um `SELECT` com **exatamente o mesmo `WHERE`** antes do `UPDATE` ou do
   `DELETE`, e conferir quantas linhas ele retorna.
2. Preferir soft delete a `DELETE`, para não esbarrar nas foreign keys — a
   maior parte do schema usa `onDelete: Restrict`:

   ```sql
   UPDATE teams SET is_deleted = true, updated_at = now() WHERE id = 7;
   ```

Se um erro deixar o prompt em `quadra!>`, nada mais é executado até um
`ROLLBACK`. Isso é proteção, não travamento.

### Deixando a saída legível

| Comando                 | Efeito                                                            |
| ----------------------- | ----------------------------------------------------------------- |
| `\x`                  | Alterna a saída expandida: um campo por linha, em vez de colunas |
| `\x auto`             | Usa o formato expandido apenas quando a linha não cabe na tela   |
| `\timing on`          | Mostra o tempo de execução de cada comando                      |
| `\pset null '(null)'` | Torna`NULL` visível, em vez de célula vazia                   |
| `\pset pager off`     | Desliga o paginador                                               |

O `\x` é o mais útil: tabelas como `users` têm colunas demais para caber na
largura do terminal.

### Rodando SQL sem abrir uma sessão

Com `-c`, direto do shell:

```bash
psql 'host=quadra-production-db.c4t06g4a8t85.us-east-1.rds.amazonaws.com port=5432 user=quadra_admin dbname=quadra sslrootcert=/certs/global-bundle.pem sslmode=verify-full' \
  -c 'SELECT count(*) FROM users WHERE is_deleted = false;'
```

Para exportar um resultado em CSV, de dentro de uma sessão:

```
\copy (SELECT id, name, slug FROM teams WHERE is_deleted = false) TO '/tmp/teams.csv' WITH CSV HEADER
```

O `\copy` grava no disco do CloudShell, que é efêmero — e não há download pela
interface. Para levar o conteúdo embora, imprima na tela e copie:

```bash
cat /tmp/teams.csv
```

### Editando e repetindo comandos

| Comando         | Efeito                                                              |
| --------------- | ------------------------------------------------------------------- |
| `↑` / `↓` | Percorre o histórico                                               |
| `Ctrl+R`      | Busca reversa no histórico                                         |
| `\e`          | Abre o último comando no editor; ao salvar e sair, executa         |
| `\g`          | Reexecuta o último comando                                         |
| `\watch 5`    | Reexecuta o último comando a cada 5 segundos;`Ctrl+C` interrompe |
| `\s`          | Mostra o histórico da sessão                                      |

O `\e` é a forma mais confortável de escrever uma consulta longa: em vez de
lutar com quebras de linha no prompt, você edita em tela cheia.

### Ajuda e saída

| Comando                | Efeito                                       |
| ---------------------- | -------------------------------------------- |
| `\?`                 | Lista todos os meta-comandos                 |
| `\h`                 | Lista todos os comandos SQL disponíveis     |
| `\h UPDATE`          | Mostra a sintaxe completa de um comando SQL  |
| `\i /tmp/script.sql` | Executa um arquivo                           |
| `\! ls /tmp`         | Roda um comando do shell sem sair da sessão |
| `\q`                 | Sai                                          |

## Executando scripts SQL

Como não há upload de arquivos, o conteúdo do script precisa ser criado dentro
do ambiente. Três formas, todas equivalentes no resultado.

### Com `cat` (colando o conteúdo)

```bash
cat > /tmp/script.sql <<'SQL'
SELECT 1;
SQL
```

As aspas simples em `<<'SQL'` são obrigatórias: sem elas o shell expande `$`, e
SQL frequentemente contém `$$` e `$1`. O delimitador final precisa estar sozinho
na linha, sem espaços antes.

Para colar em partes — útil com arquivos grandes, que alguns terminais truncam —
use `>>` a partir do segundo bloco:

```bash
cat >> /tmp/script.sql <<'SQL'
SELECT 2;
SQL
```

Confira o resultado antes de executar:

```bash
wc -l /tmp/script.sql
tail -5 /tmp/script.sql
```

### Com `nano`

```bash
nano /tmp/script.sql
```

Cole o conteúdo, salve com `Ctrl+O` e `Enter`, saia com `Ctrl+X`.

Ao colar SQL no `nano`, desative a quebra automática de linha antes
(`Esc` seguido de `$`) — caso contrário linhas longas podem ser partidas.

### Com `vim`

```bash
vim /tmp/script.sql
```

Antes de colar, entre em modo de colagem para o editor não reindentar o texto:

```
:set paste
```

Depois `i` para inserir, cole o conteúdo, `Esc`, e `:wq` para salvar e sair.

### Executando o arquivo

```bash
psql 'host=quadra-production-db.c4t06g4a8t85.us-east-1.rds.amazonaws.com port=5432 user=quadra_admin dbname=quadra sslrootcert=/certs/global-bundle.pem sslmode=verify-full' \
  -v ON_ERROR_STOP=1 -f /tmp/script.sql
```

`ON_ERROR_STOP=1` interrompe na primeira falha. Sem ele, o `psql` segue
executando as instruções seguintes sobre um estado já inconsistente.

Alternativamente, com uma sessão já aberta:

```
\i /tmp/script.sql
```

**Não cole um script inteiro no prompt do `psql`.** Comandos individuais podem
ser digitados à vontade, mas em uma colagem longa qualquer linha iniciada por
`\` é interpretada como meta-comando, e um erro no meio deixa a sessão em
transação abortada sem indicação clara de onde parou.

## Seeds

Os scripts de seed do projeto estão em `quadra-api/prisma/seeds/` e são SQL
puro, executáveis pelo procedimento acima.

**Pré-requisito: as migrations precisam estar aplicadas.** Os seeds não criam
tabelas; assumem o schema já existente. As migrations são executadas pelo
pipeline de deploy, em uma task ECS isolada, antes da atualização do serviço.
Em um banco recém-criado, sem deploy, os `INSERT` falham com
`relation ... does not exist`.

Os seeds foram escritos para o ambiente local de desenvolvimento e podem
pressupor dados preexistentes. Revise cada um antes de usá-lo na AWS.

## Problemas comuns

| Sintoma                                                 | Causa provável                                                           | Solução                                                |
| ------------------------------------------------------- | ------------------------------------------------------------------------- | -------------------------------------------------------- |
| `Connection timed out`                                | Ambiente criado com o security group do RDS, que não tem regra de saída | Apagar o ambiente e recriar com`sg-061558ae133a81fc0`  |
| `password authentication failed`                      | Senha copiada com espaço extra, ou rotacionada                           | Copiar novamente do Secrets Manager                      |
| `Connect timeout on endpoint URL` em comandos `aws` | Ambientes VPC não têm acesso à API da AWS                              | Esperado; obter os dados pelo console antes de entrar    |
| `no pg_hba.conf entry ... no encryption`              | Conexão sem TLS                                                          | Incluir`sslmode=verify-full` ou `sslmode=require`    |
| `relation ... does not exist`                         | Migrations ainda não aplicadas                                           | Executar o deploy antes de rodar seeds                   |
| Terminal parece travado após uma consulta              | O resultado está aberto no paginador                                     | Sair com`q`                                            |
| O comando não executa ao apertar`Enter`              | Falta o`;`, ou há parêntese/aspa aberta                               | Ver o prompt;`Ctrl+C` descarta a linha                 |
| `current transaction is aborted`                      | Erro dentro de uma transação aberta                                     | `ROLLBACK`                                             |
| Arquivo colado incompleto                               | Terminal truncou uma colagem grande                                       | Dividir em blocos com`cat >>` e conferir com `wc -l` |
