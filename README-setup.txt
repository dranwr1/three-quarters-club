3/4 Club — Login setup
=======================

Files:
- index.html (site with email/password login; no public sign-up)
- club-design.png (visual image used in site; upload beside index.html)
- setup-auth.sql (referenced by older setup notes; not present in this repository)
- supabase/migrations/202611030001_book_court.sql (shared Book Court schema and policies)

Shared Book Court migration
---------------------------
Before using the shared court, open Supabase Dashboard > SQL Editor and run:
supabase/migrations/202611030001_book_court.sql

The migration expects the existing public.books(id, title) and
public.members(id, user_id, name) columns to use UUID identifiers. It checks
these assumptions and duplicate member/auth links before creating the court
tables. If a preflight check fails, stop and compare it with the live schema;
do not bypass the check by changing existing IDs or point tables.

The migration adds only Book Court tables, functions, grants, indexes, and RLS.
It does not alter the book_read / book_recommendation point RPC or its values.
It adds the court tables to supabase_realtime when that publication exists.
After running it, sign in with a linked club member account and confirm that
the court status reports a successful shared-data query. A realtime status is
shown separately. The frontend does not use a service_role key.

Old browser-local court data is not deleted or uploaded automatically. After
the shared connection succeeds, use "استيراد الجلسات المحلية" in the court
section. The importer is repeat-safe and transfers only contributions and
votes belonging to the currently linked member; other local identities cannot
be verified and are intentionally skipped.

1. Confirm the existing Auth, profiles, books, members, and points setup is already configured. The older setup-auth.sql reference is not included here; the Book Court migration does not replace or modify that existing setup.
2. Supabase Dashboard > Authentication > Users > Add user:
   create exactly the three approved member accounts (email + password).
   Disable public sign-ups in Authentication settings (if enabled).
3. Authentication > URL Configuration:
   add https://dranwr1.github.io/three-quarters-club/ to Site URL / Redirect URLs.
4. Upload index.html AND club-design.png to the repository root (same folder), commit.
5. Test on one device, then sign in using the same account on another device.

Security notes:
- Do not put a Supabase service_role key in the HTML.
- Publishable/anon key is intended for browser use; RLS is what protects data.
- The SQL grants authenticated users read and insert access to books. It does not grant update/delete.
- Supabase Auth accounts must be created by an admin; this page has no sign-up button.
