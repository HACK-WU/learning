# -*- coding: utf-8 -*-
"""schema.surql —— 技术文档问答系统 · 数据模型定义

四张实体表 + 两张关系表：

  doc    文档（一篇 = 一条）
  chunk  切块（一篇切成 N 块，检索的最小单位）
  user   用户（带 tenant，权限边界的锚点）
  qlog   提问日志（可观测 + 审计）
  refs   文档 -> 文档（引用关系，图扩展的入口）
  hit    term -> chunk（自建倒排，中文检索的实现方式）

设计要点（每条都对应一次实测，不是拍脑袋）：

1. chunk.grams 是**冗余字段**：存 bigram 串，专门给 FULLTEXT 索引用。
   3.2.4 的内置分析器不会切中文，直接对 text 建全文索引查中文一条都查不到
   （cap-probe5-zh2.py 决定性实验：英文阳性对照正常，中文三组分析器全空）。

2. chunk.emb 用 HNSW 索引，DIMENSION 必须与 embed() 输出长度一致（12）。
   维数写错在定义时不报错，插入时才炸。

3. 权限写在表级，且**所有动作都显式声明**。表级 PERMISSIONS 省略 = NONE；
   末尾写 ", NONE" 会 Parse error，每个动作都得写 FOR <action>（cap-probe3 实测）。
   布尔判断一律用否定式（!= true），避免字段为 null 时误锁全员（课 10 P0）。

4. tenant 字段是行级隔离的锚点，任何查询路径都必须带上它。
"""

SCHEMA = """
-- ─────────────────────────── 复位（可重复执行）
REMOVE TABLE IF EXISTS qlog;
REMOVE TABLE IF EXISTS hit;
REMOVE TABLE IF EXISTS term;
REMOVE TABLE IF EXISTS refs;
REMOVE TABLE IF EXISTS chunk;
REMOVE TABLE IF EXISTS doc;
REMOVE TABLE IF EXISTS user;
REMOVE ACCESS IF EXISTS app ON DATABASE;
-- ⚠️ REMOVE ANALYZER 在 3.2.4 上不接受 ON DATABASE 子句，
--    写成 "REMOVE ANALYZER IF EXISTS zh_grams ON DATABASE" 会 Parse error
REMOVE ANALYZER IF EXISTS zh_grams;

-- ─────────────────────────── 分析器
-- 只做小写 + 空格切分：中文切分由应用层 bigram 负责，这里不指望分析器
DEFINE ANALYZER zh_grams TOKENIZERS blank FILTERS lowercase;

-- ─────────────────────────── 文档
DEFINE TABLE doc SCHEMAFULL TYPE NORMAL
  PERMISSIONS FOR select WHERE tenant = $auth.tenant,
                FOR create NONE, FOR update NONE, FOR delete NONE;
DEFINE FIELD title    ON doc TYPE string;
DEFINE FIELD tenant   ON doc TYPE string;
DEFINE FIELD category ON doc TYPE string;
DEFINE FIELD updated  ON doc TYPE datetime DEFAULT time::now();
DEFINE INDEX idx_doc_tenant ON TABLE doc COLUMNS tenant;

-- ─────────────────────────── 切块（检索最小单位）
DEFINE TABLE chunk SCHEMAFULL TYPE NORMAL
  PERMISSIONS FOR select WHERE tenant = $auth.tenant,
                FOR create NONE, FOR update NONE, FOR delete NONE;
DEFINE FIELD doc    ON chunk TYPE record<doc>;
DEFINE FIELD tenant ON chunk TYPE string;
DEFINE FIELD seq    ON chunk TYPE number;
DEFINE FIELD text   ON chunk TYPE string;
-- grams 是 bigram 冗余字段，专门给全文索引（见文件头设计要点 1）
DEFINE FIELD grams  ON chunk TYPE string;
DEFINE FIELD emb    ON chunk TYPE array<number>;
DEFINE INDEX idx_chunk_grams ON TABLE chunk COLUMNS grams FULLTEXT ANALYZER zh_grams BM25 HIGHLIGHTS;
DEFINE INDEX idx_chunk_emb   ON TABLE chunk FIELDS emb HNSW DIMENSION 12 DIST COSINE EFC 150 M 12;
DEFINE INDEX idx_chunk_tenant ON TABLE chunk COLUMNS tenant;

-- ─────────────────────────── 用户（权限锚点）
DEFINE TABLE user SCHEMAFULL TYPE NORMAL
  PERMISSIONS FOR select WHERE id = $auth.id,
                FOR update WHERE id = $auth.id,
                FOR create NONE, FOR delete NONE;
DEFINE FIELD email    ON user TYPE string;
DEFINE FIELD password ON user TYPE string;
DEFINE FIELD tenant   ON user TYPE string;
DEFINE FIELD name     ON user TYPE string;
DEFINE INDEX idx_user_email ON TABLE user COLUMNS email UNIQUE;

-- ─────────────────────────── 文档引用关系（图扩展入口）
DEFINE TABLE refs TYPE RELATION IN doc OUT doc
  PERMISSIONS FOR select WHERE in.tenant = $auth.tenant,
                FOR create NONE, FOR update NONE, FOR delete NONE;
DEFINE FIELD kind ON refs TYPE string DEFAULT 'refers';

-- ─────────────────────────── 倒排（中文检索核心）
DEFINE TABLE term SCHEMAFULL TYPE NORMAL
  PERMISSIONS FOR select FULL, FOR create NONE, FOR update NONE, FOR delete NONE;
DEFINE FIELD w  ON term TYPE string;
DEFINE FIELD df ON term TYPE number DEFAULT 0;
DEFINE INDEX idx_term_w ON TABLE term COLUMNS w UNIQUE;

DEFINE TABLE hit TYPE RELATION IN term OUT chunk
  PERMISSIONS FOR select WHERE out.tenant = $auth.tenant,
                FOR create NONE, FOR update NONE, FOR delete NONE;
DEFINE FIELD tf ON hit TYPE number DEFAULT 1;

-- ─────────────────────────── 提问日志
DEFINE TABLE qlog SCHEMAFULL TYPE NORMAL
  PERMISSIONS FOR select WHERE tenant = $auth.tenant,
                FOR create NONE, FOR update NONE, FOR delete NONE;
DEFINE FIELD tenant  ON qlog TYPE string;
DEFINE FIELD who     ON qlog TYPE option<record<user>>;
DEFINE FIELD q       ON qlog TYPE string;
DEFINE FIELD hits    ON qlog TYPE number;
DEFINE FIELD mode    ON qlog TYPE string;
DEFINE FIELD at      ON qlog TYPE datetime DEFAULT time::now();

-- ─────────────────────────── 访问方式（记录用户）
DEFINE ACCESS app ON DATABASE TYPE RECORD
  SIGNIN ( SELECT * FROM user WHERE email = $email AND crypto::argon2::compare(password, $password) )
  DURATION FOR TOKEN 30m, FOR SESSION 12h;
"""
