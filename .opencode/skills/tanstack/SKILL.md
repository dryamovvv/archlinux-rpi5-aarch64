---
name: tanstack
description: Use official TanStack documentation from tanstack.com when working with TanStack libraries (Query, Router, Table, Form, Start). Fetches docs via Context7.
license: MIT
compatibility: opencode
metadata:
  audience: developer
  workflow: tanstack
---

## What I do
I help you work with TanStack libraries using official documentation from tanstack.com:

- **TanStack Query v5** — server state, data fetching, caching, mutations (React/Solid/Vue/Svelte)
- **TanStack Router** — type-safe routing
- **TanStack Table** — headless table/datagrid
- **TanStack Form** — form state management
- **TanStack Start** — full-stack React framework

## When to use me
Use this skill when the user asks about any TanStack library or when writing code that uses TanStack.

## How I work
1. Identify which TanStack library the user is working with
2. Use Context7 to fetch the latest docs:
   - **TanStack Query v5**: resolve library `/websites/tanstack_query_v5`, then query docs
   - **TanStack Query (general)**: resolve library `/tanstack/query`
   - **TanStack Router/Table/Form/Start**: resolve library `/tanstack/tanstack.com`
   - **TanStack (llms.txt)**: resolve library `/llmstxt/tanstack_llms_txt`
3. Always prefer the most up-to-date version (v5 for Query)
4. Provide code examples directly from the official docs

## Important
- Always check Context7 docs before answering TanStack questions
- Prefer official API patterns over assumptions
- TanStack Query v5 has breaking changes from v4 — always verify the correct version
- Router, Table, Form, and Start are also available through `/tanstack/tanstack.com`
