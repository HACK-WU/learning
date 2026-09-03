BEGIN TRANSACTION;
LET $bal = (SELECT balance FROM ONLY account:a).balance;
IF $bal < 1000 { THROW "余额不足 1000，中止转账"; };
UPDATE account:a SET balance -= 1000;
UPDATE account:b SET balance += 1000;
COMMIT TRANSACTION;
