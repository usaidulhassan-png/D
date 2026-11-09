# License service setup (owner checklist)

This optional service does not change the local-first attendance database. Do not deploy it until you are ready to operate a central service and have tested it with a spare account.

## What is included

- `license_setup.sql`: sequential customer serials, customer and installation records, owner accounts, and usage audit events. Direct browser database access is denied.
- `functions/license/index.ts`: authenticated customer registration/verification and owner-only listing, status changes, and new-device approval.
- The app's **License & owner controls** panel calls the Edge Function. The Sync & Access login supplies a customer's authenticated identity. Add the owner Auth user's UUID to `da_license_owner_accounts` using the SQL Editor.

## Deploy when ready

1. Create a Supabase project and an Auth account for the owner. Keep the owner email/UUID private.
2. Run `setup.sql`, then `license_setup.sql` in the SQL Editor.
3. Copy the owner's Auth user UUID from Authentication → Users and run the commented owner insert at the end of `license_setup.sql`, replacing the example UUID.
4. Install the Supabase CLI, link the project, and deploy the `license` function.
5. Set `SUPABASE_SERVICE_ROLE_KEY` as a server-side Edge Function secret. Supabase supplies `SUPABASE_URL` to the function. Never put the service-role key in the app, source control, or a customer device.
6. Configure Sync & Access on a test installation using the project's URL, public/anon key, and a customer Auth account. Choose **Register / verify this device**. New customer accounts and installations start pending. The owner must activate the customer and approve its device in the owner panel before attendance is enabled.
7. Use the owner panel to activate, deactivate, block, or unblock test customers and devices. Review the corresponding event records before onboarding real customers. A backup restore must be made while signed into the same customer account that created the backup; a different installation waits for owner approval. If a backup was created before the first license registration, open it on the original device after registration and create a fresh backup so it contains the server-assigned customer serial. Older v1 backups have no customer identity and are kept compatible only while licensing is not configured.

## Signing key setup

Generate one P-256 key pair and keep the private key secret. You can generate it with Node.js from the project folder:

```sh
node -e "const {generateKeyPairSync}=require('node:crypto'); const k=generateKeyPairSync('ec',{namedCurve:'prime256v1',publicKeyEncoding:{format:'jwk'},privateKeyEncoding:{format:'jwk'}}); console.log(JSON.stringify({privateJwk:k.privateKey,publicJwk:k.publicKey}))"
```

In Supabase → Edge Functions → Secrets, set `LICENSE_PRIVATE_JWK` to the full `privateJwk` JSON object and `LICENSE_PUBLIC_JWK` to the full `publicJwk` JSON object. Keep the private JWK only in Edge Function secrets. Deploy the `license` function after setting both values. The function issues a signed ticket for seven days only when both customer and device are active; online checks reject blocked or pending accounts.

## Current limits before real licensing

- The web app uses a browser-generated installation UUID. Clearing browser storage or reinstalling may create a new ID; this is not a guaranteed hardware fingerprint.
- Customer serials are generated centrally, in sequence. They cannot be reliably assigned as global serials while each user is fully offline.
- Installation IDs are browser-generated rather than hardware-bound, and an experienced user can clear or alter browser storage. The seven-day ticket is an app-level control, not tamper-proof DRM.
- Device approval is enforced before importing a v2 backup on a different device when Sync & Access and the function are configured. Without a configured license service, backups continue to restore locally for backward compatibility.
- Admin Dashboard password and license owner authentication are separate. The local admin password is not an owner identity.
