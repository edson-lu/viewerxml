CREATE TABLE fornecedores (
    id SERIAL PRIMARY KEY,
    cnpj VARCHAR(14) UNIQUE,
    nome VARCHAR(255) NOT NULL,
    criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE notas (
    id SERIAL PRIMARY KEY,
    fornecedor_id INTEGER REFERENCES fornecedores(id) ON DELETE RESTRICT,
    chave_acesso VARCHAR(44) UNIQUE NOT NULL,
    numero_nf VARCHAR(20) NOT NULL,
    modelo CHAR(2) NOT NULL CHECK (modelo IN ('55', '65')),
    data_emissao DATE,
    valor_nf NUMERIC(15, 2) NOT NULL DEFAULT 0.00,
    nome_arquivo VARCHAR(255),
    importado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE itens_nota (
    id SERIAL PRIMARY KEY,
    nota_id INTEGER NOT NULL REFERENCES notas(id) ON DELETE CASCADE,
    codigo_produto VARCHAR(60),
    descricao VARCHAR(255) NOT NULL,
    quantidade NUMERIC(15, 4) NOT NULL DEFAULT 0,
    valor_unitario NUMERIC(15, 4) NOT NULL DEFAULT 0,
    valor_total NUMERIC(15, 2) NOT NULL DEFAULT 0
);

CREATE INDEX idx_notas_fornecedor ON notas(fornecedor_id);
CREATE INDEX idx_notas_modelo ON notas(modelo);
CREATE INDEX idx_notas_data ON notas(data_emissao DESC);
CREATE INDEX idx_notas_valor ON notas(valor_nf);
CREATE INDEX idx_notas_numero ON notas(numero_nf);
CREATE INDEX idx_notas_chave ON notas(chave_acesso);

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_fornecedores_nome_trgm ON fornecedores USING GIN (nome gin_trgm_ops);

CREATE VIEW vw_resumo AS
SELECT COUNT(*) AS quantidade_notas, COALESCE(SUM(valor_nf), 0) AS total_filtrado FROM notas;

CREATE VIEW vw_maior_fornecedor AS
SELECT f.nome AS fornecedor, SUM(n.valor_nf) AS total
FROM notas n JOIN fornecedores f ON f.id = n.fornecedor_id
GROUP BY f.nome ORDER BY total DESC LIMIT 1;

CREATE VIEW vw_lista_notas AS
SELECT
    f.nome AS fornecedor,
    n.numero_nf AS numero_nota,
    n.data_emissao AS data,
    n.valor_nf AS valor,
    (SELECT COUNT(*) FROM itens_nota i WHERE i.nota_id = n.id) AS qtd_itens
FROM notas n LEFT JOIN fornecedores f ON f.id = n.fornecedor_id
ORDER BY n.data_emissao DESC NULLS LAST;

CREATE VIEW vw_lista_notas_completa AS
SELECT
    f.nome AS fornecedor,
    f.cnpj,
    n.numero_nf AS numero_nota,
    n.modelo,
    CASE n.modelo WHEN '55' THEN 'NF-e' WHEN '65' THEN 'NFC-e' END AS tipo_documento,
    n.data_emissao AS data,
    n.valor_nf AS valor,
    (SELECT COUNT(*) FROM itens_nota i WHERE i.nota_id = n.id) AS qtd_itens,
    n.chave_acesso AS chave,
    n.nome_arquivo AS arquivo
FROM notas n LEFT JOIN fornecedores f ON f.id = n.fornecedor_id
ORDER BY n.data_emissao DESC NULLS LAST;

GRANT USAGE ON SCHEMA public TO viewer;

GRANT SELECT ON fornecedores, notas, itens_nota TO viewer;
GRANT SELECT ON vw_resumo, vw_maior_fornecedor, vw_lista_notas, vw_lista_notas_completa TO viewer;
GRANT INSERT ON fornecedores, notas, itens_nota TO viewer;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO viewer;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT ON TABLES TO viewer;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO viewer;
