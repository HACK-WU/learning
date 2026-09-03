USE NS learn;
USE DB kp41;

// ============ 4.1 CRUD 五件套 ============

// --- [1] CREATE 基础 ---
CREATE author:rowling SET name = 'J.K. Rowling', country = 'UK';
CREATE book:hp1 SET title = "Philosopher's Stone", year = 1997, price = 39.9, author = author:rowling;
CREATE book:hp2 SET title = 'Chamber of Secrets', year = 1998, price = 42.0, author = author:rowling;
CREATE book:hp3 SET title = 'Prisoner of Azkaban', year = 1999, price = 45.5, author = author:rowling;
SELECT * FROM book;

// --- [2] UPDATE 已存在的记录（正常）---
UPDATE book:hp1 SET price = 36.0;
SELECT * FROM book:hp1;

// --- [3] 关键：UPDATE 不存在的记录会怎样？（2.0 起语义变更）---
UPDATE book:not_exist SET price = 99.0;
SELECT * FROM book;

// --- [4] UPSERT 不存在的记录（应创建）---
UPSERT book:hp4 SET title = 'Goblet of Fire', year = 2000, price = 48.0;
SELECT * FROM book:hp4;

// --- [5] UPSERT 已存在的记录（应更新，且默认整体替换内容）---
UPSERT book:hp4 SET price = 50.0;
SELECT * FROM book:hp4;

// --- [6] UPSERT 已存在 + CONTENT（整体替换，未提及字段会消失）---
UPSERT book:hp4 CONTENT { title: 'Goblet of Fire', year: 2000 };
SELECT * FROM book:hp4;

// --- [7] UPSERT 已存在 + MERGE（合并，保留未提及字段）---
UPSERT book:hp4 MERGE { price: 52.0 };
SELECT * FROM book:hp4;

// --- [8] SET vs CONTENT vs MERGE 对照（在 UPDATE 上）---
UPDATE book:hp2 SET price = 40.0;
UPDATE book:hp2 CONTENT { title: 'Chamber of Secrets' };
UPDATE book:hp2 MERGE { year: 1998 };
SELECT * FROM book:hp2;

// --- [9] DELETE 与 RETURN BEFORE ---
CREATE book:tmp1 SET title = 'Temp One', price = 10;
DELETE book:tmp1 RETURN BEFORE;

// --- [10] RETURN AFTER ---
CREATE book:tmp2 SET title = 'Temp Two', price = 20;
DELETE book:tmp2 RETURN AFTER;

// --- [11] RETURN DIFF ---
CREATE book:tmp3 SET title = 'Temp Three', price = 30;
DELETE book:tmp3 RETURN DIFF;

// --- [12] RETURN NONE ---
CREATE book:tmp4 SET title = 'Temp Four', price = 40;
DELETE book:tmp4 RETURN NONE;

// --- [13] UPDATE 的 RETURN DIFF ---
UPDATE book:hp3 SET price = 47.0 RETURN DIFF;

// --- [14] 最终状态 ---
SELECT * FROM book;
