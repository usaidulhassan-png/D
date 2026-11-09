# Company workspace setup

This is the customer-owned project used for employee, attendance, face descriptor (if enabled), user, role and device data. Every customer should own this project under their own Supabase account. Do not put a service-role key in the website.

## First setup

1. Create a Supabase project for the company.
2. In **SQL Editor**, run the single consolidated `setup.sql` once. Keep your existing database tables and attendance data; this setup does not drop them. At the end, confirm every `installed` result says `true`.
3. In **Project Settings → API**, copy the Project URL and publishable/anon key. Enter those in **Sync & Access** in the app.
4. Create the first Auth account with the email that will own the company workspace. Confirm its email, then enter the company name and sign in. If no workspace exists yet, the app creates it for this first account automatically; **Create company workspace** is also available as a manual action. That account and its current installation become Company Admin and the initial offline Admin device.
5. Turn off public Auth sign-ups after the first workspace is created. Company Admins add later staff using **Company users and devices → Send invitation**. Invitees set their own password through Supabase Auth email; no password is stored in the app's team table.
6. Deploy the `team-users` Edge Function to this customer project. It uses Supabase's built-in `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` server secrets; never copy that key into the PWA.
7. To allow a signed seven-day offline attendance ticket for the Admin device, generate one P-256 key pair and set `WORKSPACE_PRIVATE_JWK` and `WORKSPACE_PUBLIC_JWK` as Edge Function secrets. Generate with Node.js:

```sh
node -e "const {generateKeyPairSync}=require('node:crypto'); const k=generateKeyPairSync('ec',{namedCurve:'prime256v1',publicKeyEncoding:{format:'jwk'},privateKeyEncoding:{format:'jwk'}}); console.log(JSON.stringify({privateJwk:k.privateKey,publicJwk:k.publicKey}))"
```

Store the private object only in Edge Function secrets. Redeploy `team-users` after setting both secrets. Without these secrets the app still works online, but the Admin device will not get an offline attendance grant.

## Users and permissions

- **Company Admin:** manages users, employee records, schedules, reports, company settings and device links. Only an active Company Admin can designate an offline Admin device.
- **Attendance operator:** can scan attendance and read employee information. Their device must be online for work actions.
- **Report viewer:** can read employee information and attendance reports but cannot scan or edit company records.

The Edge Function invites Auth users and writes their company membership. The app's role-based controls improve usability; database Row Level Security is the enforcement layer. The SQL policies restrict reads and writes by company membership and permission.

## Local and multi-device use

- Without a signed-in company account, the app remains local-first and can be used on one device with a JSON backup.
- When the Admin connects a project, local records on that browser are uploaded as the workspace's initial data. Back up first.
- Each later device enters the same company project URL and publishable key, then signs in with the invited person's own account. The Company Admin can sign in on any device with the same Admin email/password; no second Admin account is needed. Customer data remains in that project, not in the vendor license database.
- User devices need internet for attendance and changes. Only the designated Admin device can use its current signed offline attendance grant. User/device/role changes require an online Admin session.
- Face descriptors sync to the company's project so registered employees can be recognized on another device. They are biometric data. Tell employees, restrict project access, and keep a QR/manual alternative.

## Scope and limits

Each customer project can be managed by that customer. This makes the company the owner of its data, backups, project billing and project settings. The vendor cannot centrally guarantee the customer project's uptime or inspect its attendance data.

The included `license_setup.sql` and `functions/license` are a licensing prototype scoped to the Supabase project they are deployed in. They do not, by themselves, give the vendor one central view across separately owned customer projects. A separate vendor-owned license service and a customer activation flow must be configured before promising centralized sales counts or payment blocking across all customers.

The seven-day Admin offline rule is a browser-app control. Browser installation IDs are resettable and client-side software is not tamper-proof. A blocked offline device can keep working until its last ticket expires. Test roles, two separate company projects, invite/recovery, online-only user devices, offline Admin sync and conflict handling on fresh test projects before using real attendance records.
