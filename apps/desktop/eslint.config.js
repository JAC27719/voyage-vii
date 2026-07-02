import prettier from "eslint-config-prettier";
import prettierPlugin from "eslint-plugin-prettier";
import solid from "eslint-plugin-solid";
import tseslint from "typescript-eslint";

export default tseslint.config(
  ...tseslint.configs.strict,
  {
    files: ["**/*.{ts,tsx}"],
    plugins: {
      solid,
      prettier: prettierPlugin,
    },
    languageOptions: {
      parserOptions: {
        ecmaFeatures: {
          jsx: true,
        },
      },
    },
    rules: {
      ...solid.configs.typescript.rules,
      "prettier/prettier": "error",
    },
  },
  prettier,
);
