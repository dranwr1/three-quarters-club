3/4 Club — Login setup
=======================

Files:
- index.html (site with email/password login; no public sign-up)
- club-design.png (visual image used in site; upload beside index.html)
- setup-auth.sql (RLS policies)

1. Supabase Dashboard > SQL Editor: run setup-auth.sql.
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
