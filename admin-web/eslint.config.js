import tseslint from "typescript-eslint";

export default [
  { ignores: ["dist/**", "node_modules/**"] },
  ...tseslint.configs.recommended,
  {
    files: ["src/**/*.{ts,tsx}"],
    rules: {
      // These regexes intentionally reject ASCII control characters in user input.
      "no-control-regex": "off",
    },
  },
];
