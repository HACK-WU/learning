USE NS learn DB kp9;

-- ## A 无参函数
DEFINE FUNCTION fn::hello() { RETURN "hello"; };
RETURN fn::hello();

-- ## B 带类型注解参数
DEFINE FUNCTION fn::add($a: number, $b: number) { RETURN $a + $b; };
RETURN fn::add(1, 2);

-- ## C 多语句 + LET
DEFINE FUNCTION fn::greet($name: string) {
    LET $msg = "hi " + $name;
    RETURN $msg;
};
RETURN fn::greet("surreal");

-- ## D 不带 RETURN 的函数
DEFINE FUNCTION fn::noreturn() { LET $x = 1; };
RETURN fn::noreturn();

-- ## E 不带 fn:: 前缀
DEFINE FUNCTION plain_name() { RETURN 1; };

-- ## F 不用 OVERWRITE 重复定义同名函数
DEFINE FUNCTION fn::hello() { RETURN "hello2"; };

-- ## G 用 OVERWRITE 重定义
DEFINE FUNCTION OVERWRITE fn::hello() { RETURN "hello2"; };
RETURN fn::hello();

-- ## H 回显（函数定义长什么样）
INFO FOR DB;
