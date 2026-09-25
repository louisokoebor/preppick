# PrepPick meal import function

This Edge Function interprets pasted meal history into proposals. It never
writes to PrepPick's SQLite meal tables or to Supabase database tables.

The function expects the Supabase Edge Function JWT boundary to remain enabled.
No `verify_jwt = false` override is included. Authentication can be connected
when the app's account flow is added; until then, local fixture tests and
authenticated manual calls are the supported verification path.

## Secrets

Set the OpenAI key in Supabase secrets. Do not commit it or put it in Flutter:

```bash
supabase secrets set OPENAI_API_KEY=your-key
supabase secrets set OPENAI_MODEL=gpt-4o-mini
```

`OPENAI_MODEL` is optional and defaults to `gpt-4o-mini`.

## Local tests

The pure proposal validator has Deno fixture tests:

```bash
deno test supabase/functions/import-meals/index.test.ts
```

## Deploy

After the CLI is linked to the correct Supabase project:

```bash
supabase functions deploy import-meals
```

The deployed endpoint is:

```text
https://<project-ref>.supabase.co/functions/v1/import-meals
```

The request body contains `source_text`, stable `source_lines`, and a compact
`existing_library` index. The response is the strict proposal payload defined
in `schema.ts`.
