# TypeScript Standards

Project TypeScript conventions. Loaded by `ContextScout` before authoring or
reviewing code in a Node.js/TypeScript project.

## Quick Reference

**Golden Rule**: If the compiler cannot prove it, model it in the types.

- ✅ `strict` mode; `unknown` at boundaries with explicit narrowing
- ✅ Explicit types on public boundaries; inference inside function bodies
- ✅ Discriminated unions over boolean flag soup
- ✅ Immutable data; `readonly` / `ReadonlyArray` by default
- ❌ `any`, bare `as` casts, `@ts-ignore`, non-null `!` (without a documented reason)
- ❌ Floating promises, thrown strings, silent `eslint-disable`

## Compiler Discipline

- `strict: true` is the baseline; enable `noUncheckedIndexedAccess` and
  `noImplicitOverride` where the codebase allows.
- `any` is not allowed. Use `unknown` plus a type guard at the boundary.
- Never add `@ts-ignore` / `@ts-expect-error` without a specific comment and a
  reference to the underlying issue; prefer fixing the type.
- Export public API types explicitly. Never leak inferred internal types through
  a public surface.
- Type-check gate: `npx tsc --noEmit` must pass with zero errors.

## Types & Modeling

- Model states as discriminated unions, not combinations of booleans:
  ```ts
  type Job =
    | { status: "queued" }
    | { status: "running"; startedAt: Date }
    | { status: "failed"; error: Error };
  ```
- `switch` over a union must be exhaustive; use a `never` check in the default
  branch so adding a variant breaks the build.
- Use branded types for identifiers and units where string/number confusion is
  possible (`UserId`, `Cents`).
- Return `Result`-style unions at boundaries instead of throwing raw strings:
  ```ts
  type Result<T, E = Error> =
    | { ok: true; value: T }
    | { ok: false; error: E };
  ```
- Prefer `type` for unions and function types; `interface` for object contracts
  that are meant to be extended.

## Modules & Imports

- ESM first. No new `require` calls.
- Named exports; default exports only where a framework requires them.
- Use `import type { … }` for type-only imports (`verbatimModuleSyntax`).
- Resolve within the source root; use configured path aliases instead of long
  `../../..` chains.

## Async & Errors

- No floating promises: `await` them or mark with `void` explicitly.
- Async functions return `Promise<T>`; never return `Promise<any>`.
- Validate external input (HTTP, env, files) at the boundary with a schema
  library (zod/valibot) and narrow before use.
- Prefer typed error classes or result unions; never throw bare strings.

## Naming & Layout

- Files: `kebab-case.ts`; types/classes: `PascalCase`; values/functions:
  `camelCase`; constants: `SCREAMING_SNAKE_CASE`.
- One concept per file; tests colocated as `*.test.ts` or under `__tests__/`.
- Keep functions small and pure where practical; isolate side effects.

## Testing

- Use the project's runner (vitest/jest); follow Arrange-Act-Assert.
- Test behavior and public contracts, not implementation details.
- Cover the error branches of result unions and the exhaustive `never` paths.
- For complex generics, add type-level tests (`expectTypeOf`/`tsd`).

## Tooling Expectations

- `npx tsc --noEmit` — type gate, run after every wave.
- `npm test` — test gate, run after every wave.
- ESLint + Prettier as configured; fixes are applied, not suppressed.
