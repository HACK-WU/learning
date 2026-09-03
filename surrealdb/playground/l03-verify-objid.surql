USE NS learn;
USE DB kp31c;

// --- 对照实验 1：不同键名，应产生两条不同记录 ---
CREATE ok1:{ a: 1, b: 2 } SET v = 'ab';
CREATE ok1:{ a: 2, b: 1 } SET v = 'different values';
SELECT * FROM ok1;

// --- 对照实验 2：同键名不同顺序，是否同一条？（本课争议点）---
CREATE ok2:{ a: 1, b: 2 } SET v = 'ab';
CREATE ok2:{ b: 2, a: 1 } SET v = 'ba';
SELECT * FROM ok2;

// --- 对照实验 3：用 UPSERT 覆盖，看最终 v 是什么（确认是否真同一条）---
UPSERT ok2:{ b: 2, a: 1 } SET v = 'overwritten-by-ba-order';
SELECT * FROM ok2;

// --- 对照实验 4：数组 ID 顺序是否敏感？ ---
CREATE ok3:[1, 2] SET v = 'one-two';
CREATE ok3:[2, 1] SET v = 'two-one';
SELECT * FROM ok3;
