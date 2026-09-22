# RD Lot Register deployment

## 0. Upgrading an existing database (v2)

This version adds full account-tracking fields (opening/maturity date, nominee,
mobile, address, post office, passbook, KYC, account status), default-fee and
agent-commission tracking, and **live real-time sync** across every device an
agent is signed into.

If you already ran the old `supabase-schema.sql`, just run the new one again —
it is safe to re-run: it `add column if not exists`s the new fields and ends
with two `alter publication supabase_realtime add table ...` lines that turn
on live sync. If those two lines error with "already a member", live sync is
already on and you can ignore the error.


## 1. Create the shared database

1. Create a project at https://supabase.com.
2. Open **SQL Editor** and run `supabase-schema.sql`.
3. In **Authentication > Providers**, enable **Email**.
4. Choose whether email confirmation is required. If it is enabled, agents must click the confirmation link before logging in.
5. Agents can use **Sign up** to create an account, then **Log in** with email and password.
6. Run the updated SQL again if the database was created earlier, so the profile insert/update policies are added.

Existing profiles can be associated with a phone-auth user by adding the user's Auth UUID:

```sql
insert into public.profiles (id, agent_id, display_name)
values ('AUTH_USER_UUID', 'AGENT-001', 'Agent name');
```

## 2. Configure the app

Open `supabase-config.js` and add the Supabase project URL and anon key from **Project Settings > API**:

```js
window.RD_SUPABASE_CONFIG = {
  url: "https://your-project.supabase.co",
  anonKey: "your-anon-key"
};
```

Only use the anon key in this file. Never put the service-role key in browser code.

## 3. Move existing members

The original 44 records are still in the HTML seed data. In cloud mode, members come from Supabase. Add them through the app or import them with a migration script; do not put shared data in a client-side password or service key.

## 4. Deploy

Upload these files to a static host such as Netlify, Cloudflare Pages, Vercel, or GitHub Pages:

- `index.html`
- `rd-lot-app.html`
- `supabase-config.js`
- `supabase-schema.sql` (reference only; it is not served as app code)

## 5. Run the backend OCR service

OCR now runs on the backend, not in the browser. Install Node.js 20 or newer, then run from this folder:

```bash
npm install
copy backend.env.example .env
npm start
```

Set these values in `.env`:

```text
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-publishable-or-anon-key
OCR_ALLOW_ANONYMOUS=false
OCR_SPACE_API_KEY=your-ocr-space-api-key
```

Open `http://localhost:3000`. The Node service serves the app and the `/api/ocr` endpoint together. In production, deploy `server.js` to a Node host such as Render, Railway, Fly.io, or a VPS. Set `ocrUrl` in `supabase-config.js` to that service URL plus `/api/ocr` if the frontend is hosted separately.

The database is protected by row-level security, so each authenticated agent can only read and change their own members and payments.

## 6. Deploy to Vercel

This repository includes `api/ocr.js` and `vercel.json`, so Vercel can run OCR as a serverless function.

1. Push the `f:\rd` folder to a GitHub repository, or import the folder with the Vercel CLI.
2. In Vercel, choose **Add New > Project**, import the repository, and keep the default framework as **Other**.
3. Add these Vercel environment variables for **Production, Preview, and Development**:

```text
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-publishable-or-anon-key
OCR_ALLOW_ANONYMOUS=false
```

`SUPABASE_URL` and `SUPABASE_ANON_KEY` verify the signed-in user. `OCR_SPACE_API_KEY` is the hosted OCR provider key; create one at https://ocr.space/ocrapi and add it to Vercel. After adding or changing variables, use **Deployments > Redeploy**.

4. Click **Deploy**.
5. In Supabase, open **Authentication > URL Configuration** and set the Vercel URL as the Site URL, for example `https://rd-lot-register.vercel.app`.
6. Add the same URL to the allowed redirect URLs if email confirmation is enabled.

The frontend automatically calls the deployed same-origin `/api/ocr` endpoint because `ocrUrl` is empty. Do not add a service-role key to Vercel or `supabase-config.js`.

The top-right import button also accepts the India Post agent portal `.xls` export. It finds the first row containing `Account No`, `Account Name`, and `Denomination`, then imports only valid member rows. The `Select`, `Month Paid Upto`, and `Next RD Installment Due Date` columns are ignored.

## Email login requirements

- Passwords must be at least 6 characters; longer passwords are recommended.
- If email confirmation is enabled, the confirmation link must be opened before the first login.
- Never put Supabase service-role keys or user passwords in source files.

## Current behavior without configuration

If `supabase-config.js` has empty values, the app stays in local browser mode for member storage, but image OCR requires the Node backend. Cloud mode requires the Supabase SQL setup, Email provider, and config values above.
