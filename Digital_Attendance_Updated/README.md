# Digital Attendance

**Smart Face & QR Attendance System** — an offline-first PWA upgraded from the provided Offline Face Attendance Starter. Records are always saved locally first. Local mode is the default. Multi-device mode syncs through the company-owned Supabase project with individual user roles.

## Run and install

Camera APIs and service workers require a secure context. Serve this folder from `https://` or `http://localhost`; opening `index.html` directly as a file is not supported for camera use.

1. Copy the complete `Digital_Attendance` folder to a static HTTPS host or a local web server. Local mode needs no server; multi-device mode uses the company Supabase project and Edge Function.
2. Open the address in a current version of Google Chrome. On first launch, wait for the local face models to load and accept camera permission.
3. In Chrome, use **Install app** / **Add to Home screen** to install the PWA. After the first successful load, the service worker caches the app, QR library, face-recognition library and models for offline use.
4. Test offline by reopening the installed app after the first load, then switching on airplane mode.

### Windows PC

1. Keep the entire `Digital_Attendance` folder together.
2. Double-click `Start-Digital-Attendance.bat`. Leave the black server window open while using the app.
3. In Chrome open `http://localhost:8080`. After changing/updating the folder, close old app tabs and reopen this address; use Ctrl+F5 if it still shows an old page.
4. Allow camera access when prompted. Do not open `index.html` directly from File Explorer.

### Android phone

The local PC address above works only on that PC. For Android, upload the updated folder contents to an HTTPS static host, open that HTTPS address in Chrome, allow camera access, then use **Add to Home screen**. Reload the hosted site after deploying a new version. The app has no runtime CDN dependency.

For first setup, keep an internet connection on until the local app files and face models have loaded once.

## Attendance behavior

- Every employee's attendance is one daily summary: one required check-in and an optional check-out.
- Each employee is assigned Support Staff, Management Staff, or Teaching Staff and checked against that group’s start time plus one shared grace period. A scan records Present or Late and stores the scheduled time, check-in time, and minutes late.
- Check-out updates that day's summary; it cannot create a record without a check-in and can only be saved once per date.
- **Mark absent remaining** writes Absent for active employees with no record today. If one arrives later and scans, that same row becomes Present or Late. Individual attendance rows can be deleted from a daily report; deleting one allows a new check-in for that day.
- Employees with attendance history cannot be deleted; deactivate them to reject recognition and QR attendance while preserving history. Employees with no history can be deleted after confirmation.
- Employee IDs are case-insensitively unique and remain fixed once saved so historical attendance stays linked.
- CSV exports actual attendance records, with separate employee ID, name, date, status, check-in/out times and methods. Employee IDs are exported as quoted text for Excel / Access imports.

## Modules

- Employee registration and editing, optional compressed local profile photo, staff category assignment, face enrollment, active status, generated employee-ID QR display, and one-sheet print of all employee QR codes. Adding employees is open to staff; editing, activation, deactivation and deletion are admin protected. Face enrollment is optional, so QR-only records can be created and faces added later.
- Automatically migrates records from the provided starter app's `OfflineFaceAttendanceDB` into the new local database on first launch, preserving known employees and valid attendance history.
- Live face matching with locally bundled face-api runtime and Tiny Face Detector, tiny 68-point landmark and face-recognition models.
- Live QR detection with Chrome's built-in `BarcodeDetector` on the camera stream, with the bundled scanner as a QR-only fallback when needed; QR image generation uses a bundled library.
- Dashboard greeting with live clock and clickable employee/attendance totals; employee monthly profiles with Present/Late/Absent totals; mobile back navigation, an in-app update checker, and portrait camera/results scanner layout on phones; password-protected Admin Dashboard for company information, group start times and shared late grace period; employee schedule assignment overview; front/back camera selection; daily and monthly reports, row deletion, CSV and SMS-ready Excel export (only employees with saved attendance are included), JSON backup and validated merge restore.
- PWA manifest and service-worker cache for offline operation after the initial load.
- Local-first mode and customer-owned multi-device workspaces with Supabase Auth, membership roles, device approvals, Realtime, optional face descriptor sync, Admin-only seven-day offline attendance grants, team invitations and permission checks in Row Level Security. Run supabase/setup.sql and follow supabase/WORKSPACE_SETUP.md.

## Admin access

Local mode protects company settings with a device-local password. Multi-device mode uses individual Supabase Auth accounts and Company Admin roles. Do not share one staff login. The local password only locks the app interface; it does not encrypt local attendance data or replace database authorization.

## Multi-device company workspace

Local mode is the default: the app opens without an account and keeps its data in that device's browser. Use JSON backup before clearing browser data. To connect more devices, open **Sync & Access** and connect the company's own Supabase project. Each person signs in with their own email account; do not share one password across staff.

Run `supabase/setup.sql` in the customer's project. Create the first Auth account, confirm its email, sign in through the app and choose **Create company workspace**. That account becomes Company Admin. Deploy `supabase/functions/team-users/index.ts` and follow `supabase/WORKSPACE_SETUP.md`. The Admin invites users and assigns Company Admin, Attendance operator or Report viewer. The Admin panel lists users and devices and can block devices or select the one Admin device allowed to scan offline.

Customer employee records, attendance, schedules, role memberships and (if used) face descriptors stay in that customer's own Supabase project. The vendor license database is separate. The current included licensing prototype does not yet provide one central vendor dashboard across separately owned customer projects; see `WORKSPACE_SETUP.md` before offering payment blocking or central customer counts.

User devices need to be online to scan or change records. The designated Admin device can scan offline for up to seven days after receiving a signed grant from its project Edge Function. Employee, schedule, user and permission changes require the Admin to be online. This avoids other devices working with outdated company configuration. Attendance conflicts are preserved as local conflict records and shown in the sync status; do not clear browser storage while a conflict is unresolved.

Supabase Auth invitation email delivery depends on the customer's Auth email configuration. Disable public sign-ups after bootstrapping the first Company Admin; later accounts should be invited by that Admin. Never enter a service-role key in the app.

## Backup and privacy

Create a JSON backup from **Backup & Restore** before clearing browser storage, reinstalling Chrome, or moving devices. Face descriptors are biometric data; they are included in backups and cloud sync when connected. Keep backups private and restrict access to the company project. A local-only company must keep its own backup. A cloud project still needs a backup/restore plan; synchronization is not a substitute for backup.

## Face recognition and limitations

The app stores a 128-number face descriptor, not a cloud face photo. When company sync is enabled, descriptors are sent to that company's Supabase project so the other enrolled devices can recognize employees. This is sensitive biometric data. Obtain appropriate employee notice/consent, restrict access, support deletion/export, and retain QR/manual attendance. Liveness detection is not implemented, so a photo or screen replay may fool face matching.

QR payloads identify an employee ID and are not cryptographically signed. They are convenient local identifiers, not proof of identity; use supervised scanning.

## Standards and security notes

The role and database access design uses Supabase Auth plus Row Level Security and should be verified against the OWASP ASVS checklist before production release. This does not constitute an independent security audit, legal review or certification. Device IDs are browser installation IDs, not permanent hardware identities. A browser PWA can enforce online permissions and signed offline grants, but is not tamper-proof software.

- [OWASP ASVS](https://asvs.owasp.org/)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase Auth management](https://supabase.com/docs/guides/auth/managing-user-data)
## Technical structure

```text
Digital_Attendance/
├── index.html
├── manifest.webmanifest
├── sw.js
├── README.md
├── css/style.css
├── js/{app,database,employees,attendance,face-recognition,sync}.js
├── libraries/{face-api.min,html5-qrcode.min,qrcode.min}.js
├── models/                    # local face model manifests and weights
├── assets/icons/icon.svg
└── supabase/setup.sql
```

No employee data, generated backups or camera captures belong in the source repository. Third-party code and face model files are included for local operation; see `THIRD_PARTY_NOTICES.md` for license references.

## Developer

UH DATA TECH SOLUTIONS · Hyderabad, Sindh, Pakistan · Usaid ul Hassan · [0304-0307828](tel:03040307828) · [usaidulhassan@gmail.com](mailto:usaidulhassan@gmail.com)

## Verification status

JavaScript syntax, project references and service-worker precache entries were checked before delivery. The updated UI was opened locally; employee search and license panel rendering were smoke-checked. Automated JavaScript syntax and required local resource checks passed. No real attendance or cloud license changes were made during these checks. Camera-based face and QR recognition, Android installation, and offline behavior still need verification on actual supported devices with camera permissions. No liveness detection is claimed.

