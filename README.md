# 🗄️ Leitor XML — Arquitetura e Administração PostgreSQL

Implementação completa de um banco de dados relacional **PostgreSQL 16** em ambiente Linux (Ubuntu 24.04 Noble / Linux Mint), projetado para suportar a importação, armazenamento e consulta estruturada das informações de documentos fiscais eletrônicos (**NF-e modelo 55** e **NFC-e modelo 65**).

O projeto abrange todo o ciclo de vida de administração de dados: **provisionamento de servidor no Linux, modelagem relacional, otimização de consultas (tuning), segurança baseada em privilégios, rotina de backup/restore e monitoramento**.

## 🛠️ Stack e Ambiente Provisionado

* **SGBD:** PostgreSQL 16.15 (`Ubuntu 16.15-0ubuntu0.24.04.1`)

* **Sistema Operacional:** Linux (Base Ubuntu 24.04 LTS / Kernel 64-bit)

* **Pacotes Instalados:** `postgresql`, `postgresql-contrib`, `sysstat`

* **Parâmetros Iniciais do Cluster (`initdb`):**

  * `Data directory`: `/var/lib/postgresql/16/main`

  * `Encoding`: `UTF8` | `Timezone`: `America/Sao_Paulo`

  * `shared_buffers`: `128MB` | `max_connections`: `100`

  * `Autenticação`: `peer` (local) e `scram-sha-256` (host/TCP-IP via TLSv1.3)

## 0. Instalação e Provisionamento no Linux

### 0.1. Instalação dos Pacotes e Verificação do Serviço

Atualização dos repositórios APT e instalação do servidor PostgreSQL junto com o pacote `postgresql-contrib` (necessário para extensões como `pg_trgm` e `pg_stat_statements`):

```bash
sudo apt update
sudo apt install -y postgresql postgresql-contrib
```

Validação da versão instalada e do status do daemon no `systemd`:

```bash
psql --version
# psql (PostgreSQL) 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)

sudo systemctl status postgresql --no-pager
# active (exited) / enabled
```

### 0.2. Criação do Banco de Dados e Usuários (Roles)

Acesso ao console administrativo via usuário de sistema `postgres` para definição de senhas, criação do banco `viewerxml` e criação da role restrita `viewer`:

```bash
sudo -u postgres psql
```

```sql
-- Definição de senha do superusuário
ALTER USER postgres WITH PASSWORD '*****';

-- Criação do banco de dados da aplicação
CREATE DATABASE viewerxml;

-- Criação do usuário da aplicação (sem privilégios administrativos)
CREATE USER viewer WITH PASSWORD '*****';

-- Concessão de acesso de conexão ao banco
GRANT CONNECT ON DATABASE viewerxml TO viewer;
```

### 0.3. Implantação do Schema (`schema.sql`)

Organização do diretório do projeto no Linux, ajuste de permissões de leitura para que o usuário de sistema `postgres` consiga ler o arquivo DDL e execução do script:

```bash
mkdir -p ~/viewerxml
chmod 755 ~ ~/viewerxml
chmod 644 ~/viewerxml/schema.sql

# Execução do DDL no banco viewerxml
sudo -u postgres psql -d viewerxml -f ~/viewerxml/schema.sql
```

Validação das relações criadas (`\dt` para tabelas e `\dv` para views):

```text
viewerxml=# \dt
            List of relations
 Schema |     Name     | Type  |  Owner   
--------+--------------+-------+----------
 public | fornecedores | table | postgres
 public | itens_nota   | table | postgres
 public | notas        | table | postgres

viewerxml=# \dv
                 List of relations
 Schema |          Name           | Type |  Owner   
--------+-------------------------+------+----------
 public | vw_lista_notas          | view | postgres
 public | vw_lista_notas_completa | view | postgres
 public | vw_maior_fornecedor     | view | postgres
 public | vw_resumo               | view | postgres
```

### 0.4. Carga Inicial de Dados

Inserção controlada de fornecedores, notas fiscais (modelos 55 e 65) e itens detalhados utilizando cláusulas `ON CONFLICT DO NOTHING` para garantir idempotência:

```sql
-- 1. Fornecedores (Emitentes)
INSERT INTO fornecedores (cnpj, nome) VALUES
('12345678000195', 'MERCADO SAO PAULO LTDA'),
('98765432000110', 'ATACADAO DISTRIBUIDORA LTDA'),
('11223344000155', 'PAPELARIA CENTRAL LTDA')
ON CONFLICT (cnpj) DO NOTHING;

-- 2. Notas Fiscais (NF-e 55 e NFC-e 65)
INSERT INTO notas (fornecedor_id, chave_acesso, numero_nf, modelo, data_emissao, valor_nf, nome_arquivo) VALUES
(1, '35261112345678000195550010000000011000000001', '1', '55', '2026-11-10', 152.50, 'nota_1.xml'),
(2, '35261198765432000110550010000000021000000002', '2', '55', '2026-11-11', 890.00, 'nota_2.xml'),
(3, '35261111223344000155650010000000031000000003', '3', '65', '2026-11-12', 45.90, 'nota_3.xml')
ON CONFLICT (chave_acesso) DO NOTHING;

-- 3. Itens das Notas
INSERT INTO itens_nota (nota_id, codigo_produto, descricao, quantidade, valor_unitario, valor_total) VALUES
(1, '7891000100103', 'ARROZ 5KG', 2, 32.50, 65.00),
(1, '7891000200204', 'FEIJAO 1KG', 3, 9.50, 28.50),
(1, '7891000300305', 'OLEO SOJA 900ML', 2, 29.50, 59.00),
(2, '7892000100101', 'CAIXA PAPELAO 100UN', 10, 89.00, 890.00),
(3, '7893000100102', 'CADERNO 100FLS', 1, 25.90, 25.90),
(3, '7893000200203', 'CANETA AZUL CX 50UN', 1, 20.00, 20.00),
(1, '7891000400406', 'MACARRAO 500G', 4, 4.90, 19.60),
(1, '7891000500507', 'ACUCAR 1KG', 2, 6.20, 12.40),
(1, '7891000600608', 'CAFE 500G', 1, 28.90, 28.90),
(2, '7892000200202', 'FITA ADESIVA 48MM', 20, 8.50, 170.00),
(2, '7892000300303', 'SACO PLASTICO 100UN', 5, 32.00, 160.00),
(2, '7892000400404', 'ETIQUETA TERMICA ROLO', 4, 45.00, 180.00),
(3, '7893000300304', 'GRAMPEADOR METAL', 1, 42.50, 42.50),
(3, '7893000400405', 'PAPEL A4 500FLS', 2, 34.90, 69.80),
(3, '7893000500506', 'MARCADOR TEXTO CX 6UN', 1, 18.90, 18.90);
```

Validação de integridade e agregação das views após a carga:

```sql
SELECT nota_id, COUNT(*) AS qtd_itens, SUM(valor_total) AS total_itens
FROM itens_nota GROUP BY nota_id ORDER BY nota_id;
```

```text
 nota_id | qtd_itens | total_itens 
---------+-----------+-------------
       1 |         6 |      213.40
       2 |         4 |     1400.00
       3 |         5 |      177.10
```

## 1. Modelagem de Dados

O modelo foi normalizado na **3ª Forma Normal (3FN)** para evitar redundância de emitentes e garantir a integridade dos documentos fiscais importados para a base de dados.

### Diagrama Entidade-Relacionamento (DER)

```text
+-----------------------+       +-----------------------------------+       +-------------------------+
|     fornecedores      |       |               notas               |       |       itens_nota        |
+-----------------------+       +-----------------------------------+       +-------------------------+
| PK id (SERIAL)        |1     N| PK id (SERIAL)                    |1     N| PK id (SERIAL)          |
| UK cnpj (VARCHAR 14)  |-------| FK fornecedor_id (RESTRICT)       |-------| FK nota_id (CASCADE)    |
|    nome (VARCHAR 255) |       | UK chave_acesso (VARCHAR 44)      |       |    codigo_produto       |
|    criado_em          |       |    numero_nf (VARCHAR 20)         |       |    descricao            |
+-----------------------+       |    modelo (CHAR 2: '55' | '65')   |       |    quantidade (15,4)    |
                                |    data_emissao (DATE)            |       |    valor_unitario (15,4)  |
                                |    valor_nf (NUMERIC 15,2)        |       |    valor_total (15,2)     |
                                |    nome_arquivo                   |       +-------------------------+
                                |    importado_em                   |
                                +-----------------------------------+
```

### Decisões Técnicas de Modelagem

* **Idempotência na Importação:** Uso de chaves únicas (`UNIQUE`) em `fornecedores(cnpj)` e `notas(chave_acesso)` combinadas com `ON CONFLICT DO NOTHING`, impedindo duplicidade caso o mesmo XML seja processado múltiplas vezes.

* **Integridade de Exclusão:**

  * `ON DELETE RESTRICT` em `notas.fornecedor_id`: impede a exclusão acidental de um fornecedor que possua notas fiscais vinculadas.

  * `ON DELETE CASCADE` em `itens_nota.nota_id`: garante que os itens sejam removidos automaticamente caso uma nota seja expurgada pelo administrador.

* **Camada de Abstração (Views):** Criação de 4 *views* (`vw_resumo`, `vw_maior_fornecedor`, `vw_lista_notas`, `vw_lista_notas_completa`) que entregam os indicadores pré-calculados para consumo da aplicação.

## 2. Performance e Tuning

Para suportar filtros dinâmicos por fornecedor, modelo fiscal, data e número da nota sem degradação de tempo de resposta, foi implementada uma estratégia híbrida de indexação:

### Estratégia de Índices (`12 índices ativos`)

* **B-Tree Simples:** `idx_notas_fornecedor`, `idx_notas_modelo`, `idx_notas_valor`, `idx_notas_numero`.

* **B-Tree Ordenado:** `idx_notas_data ON notas(data_emissao DESC)` para acelerar a ordenação cronológica padrão da listagem.

* **GIN (Generalized Inverted Index):** `idx_fornecedores_nome_trgm USING gin (nome gin_trgm_ops)` utilizando a extensão `pg_trgm` para buscas parciais (`ILIKE '%termo%'`) de alta velocidade.

### Evidência de Plano de Execução (`EXPLAIN ANALYZE`)

Validação de uso de índice (`Index Scan`) em consulta filtrada por modelo fiscal:

```sql
EXPLAIN ANALYZE SELECT * FROM notas WHERE modelo = '55';
```

```text
                                                        QUERY PLAN                                                        
--------------------------------------------------------------------------------------------------------------------------
 Index Scan using idx_notas_modelo on notas  (cost=0.14..8.16 rows=1 width=730) (actual time=0.061..0.064 rows=2 loops=1)
   Index Cond: (modelo = '55'::bpchar)
 Planning Time: 1.966 ms
 Execution Time: 0.161 ms
```

> **Nota de Otimização (DBA Insight):** Identificou-se que a constraint `UNIQUE` na coluna `chave_acesso` já gera o índice `notas_chave_acesso_key`. O índice redundante `idx_notas_chave` foi mapeado para remoção visando reduzir o overhead de escrita (`INSERT`) em importações em lote.

## 3. Segurança
Aplicação do **Princípio do Menor Privilégio** separando as responsabilidades administrativas das operações da aplicação:

| Role / Usuário | Atributos | Permissões no Banco `viewerxml` | Finalidade | 
| ----- | ----- | ----- | ----- | 
| **`postgres`** | `Superuser, Create role, Create DB, Replication` | Controle total (`ALL PRIVILEGES`) | Administração, DDL, tuning e backups | 
| **`viewer`** | `Login` (sem privilégios administrativos) | `CONNECT`, `USAGE` (schema), `SELECT`, `INSERT` | Usuário da aplicação (importa XMLs e consulta relatórios) | 

### Teste de Operação

Conectado via sessão criptografada com o usuário `viewer`, comprovou-se o bloqueio de operação `DELETE`:

```bash
psql -U viewer -d viewerxml -h localhost
```

```sql
viewerxml=> DELETE FROM notas WHERE id = 1;
ERROR:  permission denied for table notas
```

## 4. Backup e Restore

Para garantir a continuidade do negócio, foi estruturada uma rotina de backup que oferece compressão nativa (gzip) e suporte a restauração paralela.


### Rotina Executada e Validada

1. **Geração do Dump Compactado:**

   ```bash
   mkdir -p ~/viewerxml/backup
   pg_dump -U postgres -h localhost -d viewerxml -F c -f ~/viewerxml/backup/viewerxml_backup.dump
   # Arquivo gerado: 17K (56 entradas TOC compactadas)
   ```

2. **Inspeção de Integridade do Arquivo (`pg_restore -l`):**

   ```bash
   pg_restore -l ~/viewerxml/backup/viewerxml_backup.dump | head -20
   ```

3. **Simulação de Recuperação (Restore Drill):**
   Criação de um banco isolado (`viewerxml_teste`), restauração completa do dump e validação das relações antes da limpeza do ambiente de teste:

   ```bash
   sudo -u postgres psql -c "CREATE DATABASE viewerxml_teste;"
   pg_restore -U postgres -h localhost -d viewerxml_teste ~/viewerxml/backup/viewerxml_backup.dump
   sudo -u postgres psql -d viewerxml_teste -c "\dt"
   sudo -u postgres psql -c "DROP DATABASE viewerxml_teste;"
   ```

## 5. Monitoramento

Queries de diagnóstico utilizadas para acompanhar o crescimento do banco, conexões ativas e saúde do *Autovacuum* (prevenção de *table bloat*):

### Volumetria por Tabela e Banco Total

```sql
-- Tamanho total do banco
SELECT pg_size_pretty(pg_database_size('viewerxml')) AS tamanho_banco;
-- Resultado: 7991 kB

-- Tamanho individual por tabela (Dados + Índices)
SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS tamanho
FROM pg_stat_user_tables ORDER BY 2 DESC;
-- notas: 136 kB | fornecedores: 64 kB | itens_nota: 24 kB
```

### Monitoramento de Tuplas Mortas e Autovacuum (MVCC)

Verificação de tuplas mortas (`n_dead_tup`) para garantir que não há fragmentação em disco:

```sql
SELECT relname, n_dead_tup, last_vacuum FROM pg_stat_user_tables;
```

```text
   relname    | n_dead_tup | last_vacuum 
--------------+------------+-------------
 fornecedores |          0 | 
 itens_nota   |          0 | 
 notas        |          0 | 
```

### Sessões Ativas (`pg_stat_activity`)

Monitoramento em tempo real de bloqueios (*locks*) e queries em execução:

```sql
SELECT pid, usename, state, query
FROM pg_stat_activity
WHERE datname = 'viewerxml';
```

## 📂 Estrutura do Repositório

```text
viewerxml/
├── README.md                 # documentação técnica
├── schema.sql                # tabelas, constraints, índices, views e grants
└── backup/
    └── viewerxml_backup.dump # validado via pg_restore
```

## 💻 Como Rodar
```bash
sudo -u postgres psql -c "CREATE DATABASE viewerxml;"
sudo -u postgres psql -d viewerxml -f schema.sql