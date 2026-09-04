"use strict";
// 课 7 · 补测：private（TS 软私有）与 #private（JS 硬私有）的编译产物对比
class Soft {
    softField;
    constructor(softField) {
        this.softField = softField;
    }
    getSoft() {
        return this.softField;
    }
}
class Hard {
    #hardField;
    constructor(value) {
        this.#hardField = value;
    }
    getHard() {
        return this.#hardField;
    }
}
const s = new Soft("soft-value");
const h = new Hard("hard-value");
console.log(s.getSoft(), h.getHard());
