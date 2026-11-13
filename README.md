# RuangRent Online

A mobile-friendly room rental marketplace for Malaysia. React + Vite frontend with Supabase Auth and PostgreSQL.

## Features
- Email/password tenant registration and login
- Secure administrator-mediated landlord approval
- Administrator role assigned only through trusted SQL/console
- Room browsing, search, landlord listings and availability
- Tenant booking requests, cancellation while pending
- Landlord approval/rejection and admin dashboard
- Row Level Security (RLS) guarding every database operation

## Run locally

Requires Node.js 20+ and a Supabase project.

1. Run the SQL in `supabase/schema.sql` in **Supabase Dashboard → SQL Editor** on a **new empty project** (the schema is not idempotent).
2. In **Authentication → Providers**, enable Email. In **Authentication → URL Configuration**, add your production site URL and any required redirect URLs. Turn on email confirmations for production.
3. Copy `.env.example` to `.env.local` and enter your **Supabase Project URL** and **publishable/anon key** from Supabase API settings. Never use the service-role key in a browser.
4. Run:
   ```bash
   npm install
   npm run dev
   ```
5. Create your first user through Sign up. In Supabase **Authentication → Users**, copy that user's UUID.
6. In the SQL Editor, assign your initial administrator, replacing the example UUID:
   ```sql
   update public.profiles set role = 'admin' where id = 'YOUR-AUTH-USER-UUID';
   ```
7. Log out and back in as administrator, open **Dashboard**, and approve any registered tenant as a landlord. That account can now publish rooms.

## Deploy on Vercel

1. Import [this repository](https://github.com/mukhlis9141-code/ruangrent-online) at https://vercel.com/new.
2. Framework preset: **Vite**. Build command: `npm run build`, output directory: `dist`.
3. Add environment variables in Vercel Project Settings → Environment Variables:
   - `VITE_SUPABASE_URL`: Your Supabase project URL
   - `VITE_SUPABASE_ANON_KEY`: Your **public** publishable/anon key
4. Deploy. Copy the resulting `https://...` website URL.
5. In Supabase **Authentication → URL Configuration**, set Site URL to your Vercel domain and add it to allowed redirect URLs.
6. Redeploy after changing environment variables.
7. Test sign up, verify email, login, landlord approval, listing creation, tenant booking, and landlord approval on the live URL.

## Authentication and authorization flow

1. Visitor signs up with email/password using `supabase.auth.signUp`. Supabase Auth processes passwords; the frontend does not store password hashes.
2. A database trigger creates `profiles` with role **tenant** regardless of user-supplied metadata.
3. Login uses `supabase.auth.signInWithPassword`; Supabase JS stores and refreshes its session in browser storage by default. **Never log access/refresh tokens.** Use HTTPS on deployed sites.
4. On each protected table query, **Postgres RLS validates `auth.uid()` and server-side role**. Frontend navigation is only a usability feature, not a security boundary.
5. Only trusted SQL can create the first admin. The admin may elevate tenants to landlord via `set_user_role`, which prohibits public admin elevation.
6. Booking status changes execute `set_booking_status` with server-checked ownership and transitions.

## Schema

- `profiles`: auth user ID, name, role, phone
- `rooms`: landlord, title, location, rent, image URL, availability
- `bookings`: room, tenant, message, status

See `supabase/schema.sql` for constraints, indexes, stored procedures, grants and security policies.

## Security & production notes

- Never commit real `.env` values, Supabase `service_role` keys, API secrets, or user passwords.
- Browser publishable/anon keys are designed to be public; protection comes from Auth and RLS.
- Use Supabase's built-in email confirmation, password-reset and rate-limit settings. Add CAPTCHA and abuse monitoring before broad public launch.
- Public room image URLs are external links supplied by landlords; prefer a dedicated image-upload flow with validated image types, sizes, and storage policies for production.
- Booking request data should be minimized; this MVP does not implement payments, rental contracts, identity verification, tenant messaging or calendar conflict scheduling.
- For high-assurance web sessions, consider server-side auth with HttpOnly cookies rather than browser-storage token persistence.
- Review Supabase security advisor before serving real customer data.

## Development

`npm run build` builds production assets. This starter has no automated tests yet. Test database role permissions for all three roles before production.
