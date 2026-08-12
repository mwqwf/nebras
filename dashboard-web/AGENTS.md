# AGENTS.md

## Cursor Cloud specific instructions

### Project overview
Nebras Dashboard is an admin/moderator dashboard for an Islamic educational content platform. Built with **SvelteKit 2 + Svelte 5 + Tailwind CSS 4 + Vite 7**. All persistence uses Firebase (Realtime Database, Firestore, Cloud Storage). There is no local database.

The actual application source lives in `Nebras_dashboard-main/dashboard/`. The root `package.json` and `Nebras_dashboard-main/package.json` are pass-through wrappers that forward scripts to the dashboard directory.

### Running the dev server
```bash
cd Nebras_dashboard-main/dashboard
npm run dev          # starts on http://localhost:5173
```
Or from the repo root: `npm run dev` (delegates via `--prefix`).

### Building
```bash
cd Nebras_dashboard-main/dashboard
npm run build        # Vercel adapter; output in .svelte-kit/
```

### Linting / Tests
- **No ESLint or Prettier is configured** in this repo.
- **No test framework is configured** — there are no test scripts or test files.
- The `prepare` script runs `svelte-kit sync` which regenerates types.

### Environment variables
Copy `.env.example` → `.env` inside `Nebras_dashboard-main/dashboard/`. The app runs without real Firebase credentials but authentication and data features require valid `VITE_FIREBASE_*` values and a service account JSON.

### Key caveats
- The codebase uses Arabic comments extensively; variable/function names are in English.
- The `agent.md` file in the dashboard directory is a task log from a previous agent — it is **not** an instruction file.
- The Vercel adapter is the default (`svelte.config.js`). A Node adapter is also listed as a devDependency.
- Node.js >= 20 is required (`engines` field in `package.json`).
- The build produces warnings about optional peer deps (`encoding`, `supports-color`) which are harmless.
