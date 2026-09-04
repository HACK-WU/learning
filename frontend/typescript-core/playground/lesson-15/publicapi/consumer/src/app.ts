// 使用方代码：从头到尾没变过一行。
// 变的只是 SDK 的版本 —— 有的版本它还能编过，有的不能。
import { createOrder } from "order-sdk";

export const order = createOrder({ id: "A-1", amount: 100 });
