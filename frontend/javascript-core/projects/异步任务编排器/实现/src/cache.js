// 结果缓存 —— 回扣课 9 Map + 课 12 内存泄漏
//
// 这是「决策点 3」的落地：用「有上限的 Map + LRU 淘汰」。
// 不用无界 Map（会泄漏），也不用 WeakMap（它的键必须是对象，而这里的 key 是字符串）。

export class ResultCache {
  #max;
  #map = new Map();   // 课 9：Map 保序 —— 最近用过的排在后面，队首就是最久未用的

  constructor({ max = 100 } = {}) {
    if (!Number.isInteger(max) || max < 1) {
      throw new RangeError(`缓存上限必须是 ≥ 1 的整数，收到：${max}`);
    }
    this.#max = max;
  }

  get size() { return this.#map.size; }
  get max() { return this.#max; }

  has(key) { return this.#map.has(key); }

  get(key) {
    if (!this.#map.has(key)) return undefined;
    const value = this.#map.get(key);
    // LRU：命中后挪到队尾（先删再插，利用 Map 的插入顺序）
    this.#map.delete(key);
    this.#map.set(key, value);
    return value;
  }

  set(key, value) {
    if (this.#map.has(key)) this.#map.delete(key);
    this.#map.set(key, value);
    // 超过上限就淘汰最久未用的（队首）—— 这是「无界 Map」和「有界缓存」的分界线
    while (this.#map.size > this.#max) {
      const oldest = this.#map.keys().next().value;   // 课 9：迭代器手动取第一个
      this.#map.delete(oldest);
    }
    return this;
  }

  clear() { this.#map.clear(); }

  // 课 9：让它也能被 for...of
  *[Symbol.iterator]() {
    yield* this.#map;
  }
}
