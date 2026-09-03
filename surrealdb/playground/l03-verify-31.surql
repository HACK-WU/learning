// ================= 知识点 3.1：记录 ID 补充实测 =================
USE NS learn;
USE DB kp31;

// --- 修正：带引号的字符串 ID 必须用反引号 ---
CREATE t_str:`1` SET kind = 'string one';
CREATE t_num:1 SET kind = 'number one';
SELECT * FROM t_str;
SELECT * FROM t_num;

// --- 反引号 ID 与数字 ID 是否冲突（同表内）---
CREATE t_demo:`1` SET kind = 'string one';
CREATE t_demo:1 SET kind = 'number one';
SELECT * FROM t_demo;

// --- 带特殊字符的 ID（含空格、连字符）---
CREATE user:`john-doe` SET name = 'John Doe';
CREATE user:`alice wu` SET name = 'Alice Wu';
SELECT * FROM user;

// --- 范围查询：只给第一个元素做前缀扫描 ---
SELECT * FROM temperature:['London']..=['London', d'2026-09-09'];

// --- 半开区间与开区间 ---
SELECT * FROM temperature:['London', d'2026-09-02']..['London', d'2026-09-05'];

// --- ID 部分取值 ---
SELECT id, id[0] AS city_name, id[1] AS day FROM temperature;

// --- 对象 ID 的字段顺序敏感性 ---
CREATE obj_demo:{ a: 1, b: 2 } SET v = 'ab';
CREATE obj_demo:{ b: 2, a: 1 } SET v = 'ba';
SELECT * FROM obj_demo;
