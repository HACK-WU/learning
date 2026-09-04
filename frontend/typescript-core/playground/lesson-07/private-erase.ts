// 课 7 · 补测：private（TS 软私有）与 #private（JS 硬私有）的编译产物对比

class Soft {
  constructor(private softField: string) {}
  getSoft(): string {
    return this.softField;
  }
}

class Hard {
  #hardField: string;
  constructor(value: string) {
    this.#hardField = value;
  }
  getHard(): string {
    return this.#hardField;
  }
}

const s = new Soft("soft-value");
const h = new Hard("hard-value");
console.log(s.getSoft(), h.getHard());
