import tseslint from "typescript-eslint";

export default tseslint.config(
  // recommendedTypeChecked = 需要类型信息才能工作的那批规则
  ...tseslint.configs.recommendedTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        // 类型感知 lint 的关键：告诉 parser 去哪找 tsconfig
        project: "./tsconfig.json",
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      // 额外示范一条纯「类型感知」规则：条件永远是真 / 假
      "@typescript-eslint/no-unnecessary-condition": "error",
    },
  },
  // 配置文件本身是 .js，不在 tsconfig 的 include 里
  // —— 不给它关掉类型感知规则，它连解析都过不去
  {
    files: ["**/*.js"],
    ...tseslint.configs.disableTypeChecked,
  },
);
