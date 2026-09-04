// TS 的协变数组是「故意不安全」的——这条能跑到运行时才出问题。
interface Animal {
  name: string;
}
interface Dog extends Animal {
  breed: string;
}

const dogs: Dog[] = [{ name: "rex", breed: "labrador" }];

// 协变：Dog[] 可以赋给 Animal[]
const animals: Animal[] = dogs;

// 于是你可以往「Animal 数组」里塞一个不是 Dog 的东西 —— 编译通过
animals.push({ name: "generic-animal" });

// 但 dogs 和 animals 是同一个数组！
console.log("dogs.length =", dogs.length);
console.log("dogs[1].breed =", dogs[1].breed); // 运行时：undefined（不是 Dog！）
