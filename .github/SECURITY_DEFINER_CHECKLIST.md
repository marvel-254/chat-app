# SECURITY DEFINER Migration Review Checklist

Use this checklist when reviewing any PR that adds or modifies
`SECURITY DEFINER` functions in `supabase/migrations/`.

## Before Approving

- [ ] **search_path**: The function sets `set search_path = ''` explicitly.
  - `set search_path = public` is **not acceptable** — it allows search-path hijacking.
- [ ] **Qualified names**: Every table and function reference inside the body
  uses a schema-qualified name (e.g. `public.profiles`, not just `profiles`).
- [ ] **Auth check**: The function validates `auth.uid()` is not null at the
  start (unless it is a trigger that cannot run without an auth context).
- [ ] **Input validation**:
  - Caller identity matches declared parameters (e.g. `my_id = auth.uid()`).
  - Self-referential calls are rejected (e.g. self-DMs).
  - Foreign-key targets exist before the operation proceeds.
- [ ] **Execute grants**: `revoke execute on function ... from public` is
  present, and `grant execute ... to authenticated` limits callers.
- [ ] **No sensitive data leakage**: The function does not return internal
  IDs, error details, or row data that the caller should not see via RLS.
- [ ] **Transaction safety**: The function uses `create or replace` and
  wraps multi-step operations in a single transaction (implicit for PL/pgSQL).

## Quick Grep Commands

Run these in `supabase/migrations/` to find issues:

```bash
# Find SECURITY DEFINER without search_path = ''
grep -rn "security definer" . | grep -v "search_path = ''"

# Find unqualified table references inside SECURITY DEFINER functions
# (manual review needed — look for bare table names without public. prefix)

# Find functions missing auth.uid() checks
grep -A20 "security definer" *.sql | grep -v "auth.uid"
```

## References

- PostgreSQL docs: [SECURITY DEFINER](https://www.postgresql.org/docs/current/sql-createfunction.html#SQL-FUNCTION-SQL-BODY)
- Supabase docs: [Row Level Security](https://supabase.com/docs/guides/auth/row-level-security)
- Search-path hijacking: [OWASP](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html)
