# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

## Project state

`apparel-flow-erp` is a fresh `create-next-app` scaffold (one commit); no ERP domain code, data layer, or test framework exists yet. `app/page.tsx` is still the default starter page.

## Commands

- `npm run dev` — dev server at http://localhost:3000 (Turbopack). Running it rewrites the managed block in `AGENTS.md`; commit that change rather than reverting it.
- `npm run build` — production build; also the main type check (there is no separate `tsc` script — use `npx tsc --noEmit` for a quick check).
- `npm run lint` — ESLint 9 flat config (`eslint.config.mjs`, extends `eslint-config-next` core-web-vitals + typescript). Lint one file with `npx eslint path/to/file.tsx`.
- No test runner is configured.

## Stack and non-default configuration

- **Next.js 16.4 / React 19.3, App Router only** (`app/`). Versions are newer than most training data — check `node_modules/next/dist/docs/` (`01-app/`, `03-architecture/`) before using an API you aren't sure of.
- `next.config.ts` enables flags that change rendering/caching semantics, so read the docs for them before writing data-fetching code:
  - `cacheComponents: true` — Cache Components model (`"use cache"`, dynamic-by-default rendering, Suspense boundaries for uncached data).
  - `partialPrefetching: true`
  - `experimental.agentFeedback: true`
- **Tailwind CSS v4** is wired through a Turbopack loader rule (`@tailwindcss/turbopack` on `*.css` in `next.config.ts`), not PostCSS — there is no `postcss.config` or `tailwind.config`. Theme tokens live in `app/globals.css` via `@import "tailwindcss"` and `@theme inline`; light/dark colors are CSS variables switched by `prefers-color-scheme`.
- Typed route helpers are globally available (e.g. `LayoutProps<"/">` in `app/layout.tsx`); types are generated into `.next/types` / `.next/dev/types` by dev/build.
- Path alias `@/*` maps to the repo root (`tsconfig.json`). TypeScript is `strict`.
- Fonts: Geist / Geist Mono via `next/font/google`, exposed as `--font-geist-sans` / `--font-geist-mono` and mapped to Tailwind `font-sans` / `font-mono`.
