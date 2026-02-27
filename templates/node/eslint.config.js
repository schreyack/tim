// TIM Design Standards - ESLint Configuration for Node.js/TypeScript
// Uses ESLint flat config (v9+)

import eslint from "@eslint/js";
import tseslint from "typescript-eslint";
import security from "eslint-plugin-security";
import prettier from "eslint-config-prettier";

export default tseslint.config(
  // Base ESLint recommended rules
  eslint.configs.recommended,

  // TypeScript strict type-checked rules
  ...tseslint.configs.strictTypeChecked,

  // TypeScript stylistic rules
  ...tseslint.configs.stylisticTypeChecked,

  // Prettier compatibility (disables conflicting rules)
  prettier,

  // Global configuration
  {
    languageOptions: {
      parserOptions: {
        project: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },

  // Main source files configuration
  {
    files: ["src/**/*.ts"],
    plugins: {
      security,
    },
    rules: {
      // =======================================================================
      // TYPE SAFETY - These are HARD REQUIREMENTS
      // =======================================================================
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-unsafe-assignment": "error",
      "@typescript-eslint/no-unsafe-call": "error",
      "@typescript-eslint/no-unsafe-member-access": "error",
      "@typescript-eslint/no-unsafe-return": "error",
      "@typescript-eslint/no-unsafe-argument": "error",
      "@typescript-eslint/explicit-function-return-type": [
        "error",
        {
          allowExpressions: true,
          allowTypedFunctionExpressions: true,
          allowHigherOrderFunctions: true,
        },
      ],
      "@typescript-eslint/explicit-module-boundary-types": "error",
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/no-misused-promises": "error",
      "@typescript-eslint/await-thenable": "error",
      "@typescript-eslint/require-await": "error",
      "@typescript-eslint/strict-boolean-expressions": [
        "error",
        {
          allowString: false,
          allowNumber: false,
          allowNullableObject: false,
        },
      ],

      // =======================================================================
      // SECURITY RULES - From eslint-plugin-security
      // =======================================================================
      "security/detect-object-injection": "error",
      "security/detect-non-literal-regexp": "error",
      "security/detect-non-literal-fs-filename": "error",
      "security/detect-eval-with-expression": "error",
      "security/detect-no-csrf-before-method-override": "error",
      "security/detect-possible-timing-attacks": "warn",
      "security/detect-pseudoRandomBytes": "error",
      "security/detect-child-process": "warn",
      "security/detect-buffer-noassert": "error",

      // =======================================================================
      // COMPLEXITY LIMITS - Critical for AI development
      // =======================================================================
      "complexity": ["error", 10],                    // Cyclomatic complexity
      "max-depth": ["error", 4],                      // Max nesting depth
      "max-lines-per-function": [
        "error",
        { max: 50, skipBlankLines: true, skipComments: true },
      ],
      "max-params": ["error", 5],                     // Max function parameters
      "max-nested-callbacks": ["error", 3],           // Max callback nesting

      // =======================================================================
      // CODE QUALITY
      // =======================================================================
      "no-console": "error",
      "@typescript-eslint/no-unused-vars": [
        "error",
        {
          argsIgnorePattern: "^_",
          varsIgnorePattern: "^_",
        },
      ],
      // Disabled: conflicts with no-fallback-defaults hook.
      // no-fallback-defaults is the substantive rule (fail loudly on missing values);
      // prefer-nullish-coalescing is style that forces the exact syntax it bans.
      "@typescript-eslint/prefer-nullish-coalescing": "off",
      "@typescript-eslint/prefer-optional-chain": "error",
      "@typescript-eslint/no-unnecessary-condition": "error",
      "@typescript-eslint/no-non-null-assertion": "error",
      "@typescript-eslint/consistent-type-imports": [
        "error",
        { prefer: "type-imports" },
      ],
      "@typescript-eslint/consistent-type-exports": [
        "error",
        { fixMixedExportsWithInlineTypeSpecifier: true },
      ],

      // =======================================================================
      // ERROR HANDLING
      // =======================================================================
      "@typescript-eslint/only-throw-error": "error",
      "@typescript-eslint/prefer-promise-reject-errors": "error",
      "@typescript-eslint/use-unknown-in-catch-callback-variable": "error",

      // =======================================================================
      // NAMING CONVENTIONS
      // =======================================================================
      "@typescript-eslint/naming-convention": [
        "error",
        {
          selector: "variable",
          format: ["camelCase", "UPPER_CASE", "PascalCase"],
          leadingUnderscore: "allow",
        },
        {
          selector: "function",
          format: ["camelCase", "PascalCase"],
        },
        {
          selector: "typeLike",
          format: ["PascalCase"],
        },
        {
          selector: "enumMember",
          format: ["UPPER_CASE", "PascalCase"],
        },
      ],
    },
  },

  // Test files - relaxed rules
  {
    files: ["tests/**/*.ts", "**/*.test.ts", "**/*.spec.ts"],
    rules: {
      // Allow any in tests for mocking flexibility
      "@typescript-eslint/no-explicit-any": "off",
      "@typescript-eslint/no-unsafe-assignment": "off",
      "@typescript-eslint/no-unsafe-member-access": "off",
      "@typescript-eslint/no-unsafe-call": "off",
      "@typescript-eslint/no-unsafe-return": "off",
      "@typescript-eslint/no-unsafe-argument": "off",
      // Allow non-null assertions in tests (test data is controlled)
      "@typescript-eslint/no-non-null-assertion": "off",
      // KEEP floating-promises as error - causes real bugs in tests
    },
  },

  // Configuration files
  {
    files: ["*.config.ts", "*.config.js"],
    rules: {
      "@typescript-eslint/no-require-imports": "off",
    },
  },

  // Ignore patterns
  {
    ignores: [
      "node_modules/**",
      "dist/**",
      "build/**",
      "coverage/**",
      "*.js",
      "!*.config.js",
    ],
  }
);
