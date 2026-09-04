var __classPrivateFieldGet = (this && this.__classPrivateFieldGet) || function (receiver, state, kind, f) {
    if (kind === "a" && !f) throw new TypeError("Private accessor was defined without a getter");
    if (typeof state === "function" ? receiver !== state || !f : !state.has(receiver)) throw new TypeError("Cannot read private member from an object whose class did not declare it");
    return kind === "m" ? f : kind === "a" ? f.call(receiver) : f ? f.value : state.get(receiver);
};
var __classPrivateFieldSet = (this && this.__classPrivateFieldSet) || function (receiver, state, value, kind, f) {
    if (kind === "m") throw new TypeError("Private method is not writable");
    if (kind === "a" && !f) throw new TypeError("Private accessor was defined without a setter");
    if (typeof state === "function" ? receiver !== state || !f : !state.has(receiver)) throw new TypeError("Cannot write private member to an object whose class did not declare it");
    return (kind === "a" ? f.call(receiver, value) : f ? f.value = value : state.set(receiver, value)), value;
};
var _Counter_count;
// 课 10 · target 对比：不同 target 对产物的降级程度
class Counter {
    constructor() {
        _Counter_count.set(this, 0);
    }
    increment() {
        __classPrivateFieldSet(this, _Counter_count, __classPrivateFieldGet(this, _Counter_count, "f") + 1, "f");
    }
    get value() {
        return __classPrivateFieldGet(this, _Counter_count, "f");
    }
}
_Counter_count = new WeakMap();
const list = [1, 2, 3];
const counter = new Counter();
counter.increment();
export const result = { last: list.at(-1), count: counter.value };
