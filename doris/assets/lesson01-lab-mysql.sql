-- 第一课实测：行存 vs 列存的聚合代价（MySQL 8.0 侧）
-- 目标：用一台普通机器上的真实数据，量化"分析型查询为什么在行存上慢"

DROP TABLE IF EXISTS orders;

CREATE TABLE orders (
  id          BIGINT       NOT NULL AUTO_INCREMENT,
  order_date  DATE         NOT NULL,
  province    VARCHAR(16)  NOT NULL,
  city        VARCHAR(32)  NOT NULL,
  user_id     BIGINT       NOT NULL,
  product_id  INT          NOT NULL,
  category    VARCHAR(32)  NOT NULL,
  quantity    INT          NOT NULL,
  amount      DECIMAL(10,2) NOT NULL,
  pay_type    VARCHAR(16)  NOT NULL,
  status      TINYINT      NOT NULL,
  remark      VARCHAR(255) NOT NULL DEFAULT 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
  created_at  DATETIME     NOT NULL,
  updated_at  DATETIME     NOT NULL,
  PRIMARY KEY (id),
  KEY idx_date (order_date)
) ENGINE=InnoDB;

DELIMITER $$
CREATE PROCEDURE gen_orders(IN n_rows INT)
BEGIN
  DECLARE i INT DEFAULT 0;
  DECLARE batch INT DEFAULT 0;
  SET autocommit = 0;
  WHILE i < n_rows DO
    INSERT INTO orders
      (order_date, province, city, user_id, product_id, category,
       quantity, amount, pay_type, status, remark, created_at, updated_at)
    VALUES
      (DATE_ADD('2025-01-01', INTERVAL FLOOR(RAND()*730) DAY),
       ELT(1+FLOOR(RAND()*8), '广东','江苏','浙江','山东','四川','河南','湖北','福建'),
       CONCAT('city-', 1+FLOOR(RAND()*50)),
       1+FLOOR(RAND()*5000000),
       1+FLOOR(RAND()*200000),
       ELT(1+FLOOR(RAND()*10), '手机数码','家用电器','服饰鞋包','食品生鲜','美妆个护',
                               '母婴玩具','运动户外','家居建材','图书文娱','汽车用品'),
       1+FLOOR(RAND()*5),
       ROUND(10 + RAND()*5000, 2),
       ELT(1+FLOOR(RAND()*4), 'alipay','wechat','card','balance'),
       FLOOR(RAND()*3),
       'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
       NOW(), NOW());
    SET i = i + 1;
    SET batch = batch + 1;
    IF batch >= 20000 THEN
      COMMIT;
      SET batch = 0;
    END IF;
  END WHILE;
  COMMIT;
  SET autocommit = 1;
END$$
DELIMITER ;

-- 2000 万行：跑得动，且与 3 亿行呈线性趋势（课文中按比例换算）
CALL gen_orders(20000000);

SELECT COUNT(*) AS total_rows FROM orders;

-- 表物理大小：行存把每一行所有列都写进去了
SELECT
  ROUND(data_length/1024/1024)        AS data_mb,
  ROUND(index_length/1024/1024)       AS index_mb,
  ROUND((data_length+index_length)/1024/1024) AS total_mb
FROM information_schema.tables
WHERE table_schema='shop' AND table_name='orders';
