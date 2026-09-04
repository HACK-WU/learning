interface Animal {
  name: string;
}
interface Dog extends Animal {
  breed: string;
}

// ① 对象属性位置：协变
declare let dogObj: { d: Dog };
declare let animalObj: { d: Animal };
animalObj = dogObj; // L11 ✅ 通过
dogObj = animalObj; // L12 ❌ 两种配置下都报错

// ② 返回值位置：协变（安全方向是 Dog → Animal）
type Getter<T> = () => T;
declare let getDog: Getter<Dog>;
declare let getAnimal: Getter<Animal>;
getAnimal = getDog; // L18 ✅ 通过
getDog = getAnimal; // L19 ❌ 两种配置下都报错

// ③ 参数位置（函数属性语法）：逆变
type Setter<T> = (v: T) => void;
declare let setDog: Setter<Dog>;
declare let setAnimal: Setter<Animal>;
setDog = setAnimal; // L25 ✅ 通过（逆变允许「参数更宽」的函数）
setAnimal = setDog; // L26 ❌ 仅在 strictFunctionTypes: true 下报错

// ④ 方法语法 vs 函数属性语法 —— 本知识点的核心差异
interface MethodStyle {
  m(v: Dog): void; // 方法语法
}
interface PropStyle {
  m: (v: Dog) => void; // 函数属性语法
}
declare let methodHolder: MethodStyle;
declare let propHolder: PropStyle;
declare let hostA: { m(v: Animal): void };
declare let hostB: { m: (v: Animal) => void };

hostA = methodHolder; // L40 ✅ 即使 strictFunctionTypes 也通过 —— 方法参数是「双变」的
hostB = propHolder; //   L41 ❌ 仅在 strictFunctionTypes: true 下报错

// ⑤ 数组协变：TS 故意接受的「不安全」行为
declare let dogs: Dog[];
declare let animals: Animal[];
animals = dogs; // L46 ✅ 允许（但不安全，见 unsound-array.ts）
dogs = animals; // L47 ❌ 不允许

export {};
