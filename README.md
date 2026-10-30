# Unique Energy Service Desk

A lightweight service desk tailored to Unique Energy's energy-service operations. The web interface runs on GitHub Pages; Supabase provides staff authentication and a shared PostgreSQL database. No server secrets are shipped to the browser.

## Features

- Customer/site intake, service category, contact channel, priority and follow-up date.
- Dispatcher/manager assignment, technician updates, escalation, pending-parts and pending-customer stages.
- Work activities and completion outcomes recorded in the timeline.
- Resolution summary and customer-feedback checks before closure.
- Server-generated ticket numbers, immutable history through the API, and version checks that reject stale writes.
- Material usage against 37 catalogue items, staff workload, category reports, CSV and full JSON exports.
- Responsive layout and a clearly separate browser-only demo at `demo.html`.

The supplied CSV is a set of master lists, not historical ticket records. It supplies 10 statuses, 16 service categories, 5 teams, 10 activity types, 11 private staff-directory entries and 37 material items. Staff emails and phone numbers from the original file stay in protected database tables. The public demo uses fictional staff names and customer records.

## First deployment

1. Run `database/schema.sql` **once**, then apply `database/migrations/002_legacy_continuity.sql` and `database/migrations/003_energy_access.sql` in your Supabase project's SQL Editor. For an existing installation, apply only unapplied migrations. It creates two tables and the guarded save-ticket function in one transaction. For an existing installation, write an incremental migration rather than rerunning this initializer.
2. Set the Project URL and **publishable** key in `config.js`. Never use a secret or `service_role` key.
3. In GitHub repository **Settings → Pages**, choose **GitHub Actions**. Push to `main` to run `.github/workflows/pages.yml`. Only the six website files are included in the published artifact.
4. In Supabase **Authentication → URL Configuration**, set the Site URL to the final Pages URL, including its repository path and trailing slash. Add that exact URL to allowed redirect URLs. Invite/password-reset emails return here.
5. In **Authentication → Sign In / Providers**, disable new user signups; provision staff centrally. Disable anonymous sign-ins. Use suitable password protection and company email delivery before wider rollout.
6. Invite a staff user from **Authentication → Users**. Invitations send email: do this only for intended staff. The recipient follows the link and sets their own password in the app. If using Supabase's default mail service, check its recipient restrictions; configure your organisation's SMTP for staff rollout.
7. Add their profile using their Auth user UUID, exact name, and role:

```sql
insert into public.profiles (id, name, role)
values ('AUTH-USER-UUID-HERE', 'Staff Name', 'admin');
```

Use `manager`, `dispatcher`, or `technician` for subsequent users. After bootstrap, use the administrator-only Team access screen for invitations, role changes and deactivation; there is no self-service role elevation. Do not grant admin based solely on an email address embedded in a request.

## Permissions

All active staff can read the company service queue and active staff names/roles for coordination. The application does not provide a customer portal or isolate records by branch. Managers, dispatchers and admins can create tickets and edit ownership, priority and all workflow stages. Technicians can update status, follow-up date, resolution, satisfaction and materials only on their own assigned tickets; they cannot newly close/cancel tickets or change assignment/intake fields. Database checks enforce this even if the browser is modified. No public reads or direct client inserts, updates or deletes are granted. Work history is appended in the save transaction and includes the actual resulting data, independently of the submitted note.

Deactivate a profile with `update public.profiles set active=false where id='UUID';`. The next database request checks active membership. Account/password administration stays in Supabase Auth. Use unique names matching the intended assignee; user UUIDs are used for authentication.

## Usage

Dispatch creates a ticket, chooses a follow-up date, and assigns a member of staff. The technician records the work activity and completion result, notes any customer contact, and adds materials used. They resolve with a summary, then dispatch records customer feedback and closes. Reopen by selecting an active stage and recording the next follow-up date. Waiting tickets still count as overdue once their follow-up date passes. This is a follow-up tracker, not a negotiated SLA engine. Refresh the page to retrieve colleagues' latest changes; stale writes fail without replacing the newer ticket.

Use `demo.html` for management review. It never connects to Supabase and stores fictional records locally. Local demo data is not copied to the shared database. Production does not fall back to demo on a connection failure.

## Preview locally

From this folder, run:

```sh
python3 -m http.server 4173 --bind 127.0.0.1
```

Visit `http://127.0.0.1:4173/demo.html`. Visit the root for the configured shared version. Modern browsers and HTTPS (or localhost for preview) are required.

## Backups and later server migration

Download full JSON exports for a portable record of tickets, material usage and events. Keep exports with company-protected files. CSV is for reporting and omits the full timeline. JSON exports are not a database restore mechanism; take PostgreSQL backups through the Supabase-supported backup/export process and test recovery before relying on this for critical operations.

The interface consists of portable HTML/CSS/JavaScript and can be hosted on nginx or another static web server. For the simplest move, host the interface on the new server while retaining Supabase. To move the entire service, migrate PostgreSQL tables, sequences, functions and policies, then choose either a self-hosted Supabase stack (including Auth) or a replacement authenticated API. Auth accounts do not migrate by importing the two public tables alone. Update the adapter functions `request`, `loadShared` and `saveTicket` in `app.js` if replacing the API. Change the Auth Site URL and redirects to the new origin. Test roles, stale writes and recovery before switching staff over.

## Current boundaries

No attachments, automated customer email/WhatsApp notifications, inventory balances, scheduled SLA escalations or real-time subscriptions are included. Administrator-only membership management and staff invitation emails are included. Selecting WhatsApp records a communication event; it does not send a message. Material quantities are usage records, not stock deductions. The material catalogue and operational dropdowns are versioned in `lists.js`. Font files are loaded from Google Fonts, with local sans-serif fallbacks.

The JSON/data API is designed for an initial small team; the current UI loads the visible company queue at sign-in. Add server-side pagination and date-bounded reporting before the queue grows large. Sessions live in the current tab's session storage and tokens are refreshed when needed. Use normal sign-out on shared devices.


## Continuity from an existing workbook

Imported records keep the exact original ticket number. The protected `legacy_source` column retains original ticket fields, technical-activity fields, source sheet/row, import timestamp and source fingerprint. The ticket detail shows original service-request number, contact information, invoice, internal notes and data-quality issues, with the full original fields available in a disclosure. JSON exports include this provenance. The original workbook is not modified.

A missing or invalid original creation date stays null; it is not replaced with the import date. A valid original SLA target supplies the initial due / follow-up calendar date and its exact original timestamp remains in provenance. Missing source due dates can stay blank on existing imported records. New tickets still require a valid date. The contact channel is `Not recorded` if the workbook did not capture it. Only submitted registers are imported; unsaved intake/manager form values are not operational history.

An imported historical assignee stays attached even before that person has an account. Managers can continue editing the record without silently losing this assignment. Reassignments still require active staff, and an imported name does not grant authentication or broader access. Add an invited staff account with the matching unique display name to enable that technician's access. The team workload view includes historical assignees explicitly labelled as awaiting an account.

Private import SQL and customer extracts must never be committed to this public repository. Migration inserts should use deterministic identity, duplicate-number protection, a transaction and a post-import reconciliation. Existing live tickets must never be overwritten by a workbook re-import. `database/verify_legacy.sql` exercises continuity cases with rollback-only fictional fixtures. Legacy source metadata remains outside the writeable payload of `save_ticket`.


## Energy access and workbook work areas

The approved `profiles` table is the Energy membership allowlist. An Auth account, a matching email domain, or an active entry in the old workbook directory does not grant access on its own. Public signup, anonymous login and social providers are disabled in the selected project. Only an approved active administrator can invite accounts and approve membership. Deactivation is checked by the database on every request; the open interface also checks membership on focus and every minute.

Deploy `supabase/functions/energy-members/index.ts` as the `energy-members` Edge Function using the accompanying configuration. The handler validates the caller through Supabase Auth and checks their active admin profile before using the server-only invitation credential. The membership approval RPC runs with the caller's identity, so a revoked administrator cannot approve membership while an invitation is being sent. Never copy function environment secrets into `config.js` or browser code. The legacy-only gateway JWT switch is off because the handler performs authoritative user validation and supports current JWT signing keys. Its unauthenticated and invalid-token responses have been checked.

**Team access** invites a named colleague, sets one of four roles, lists approved accounts and changes active status. You cannot remove your own administrator access or leave the app without an active admin. Approval and role/status changes are logged in `energy_access_audit`, readable only by administrators. Use the same exact display name as the original assignee when adding a technician who should continue historical work, or reassign those tickets to the new profile through a manager.

**Tech** records activity type, completion, explicit start/end times, vehicle, action and notes on an assigned ticket. **Manager** records customer contact, channel, follow-up, satisfaction, escalation, next action and status/manager notes. These append to the ticket history. **Ticket report** joins current ticket fields with original service-request/invoice/source fields and all activity/material history; use the browser print dialog to print or save PDF. **Lists** shows the protected original directory, all dropdown sets, the material catalogue link and automatic ticket selection. The old spreadsheet submit buttons and derived report formulas are represented by web forms and live views, not copied Office scripts.

`staff_directory` and `reference_lists` were populated from private source extracts. Those extracts and real invitation recipients must not be committed to this public repository. The database source directory has 11 people and 37 catalogue items; the public demo deliberately uses a smaller fictional roster. Listing a person is distinct from approving an account.

Run `database/verify_energy_access.sql` alongside the existing permission/legacy tests to verify outsider denial, self-approval/promotion denial, administrator-only management and deactivation. All fixtures roll back. Email delivery still depends on the configured Supabase mail provider; check the recipient's inbox and use your organisation's SMTP configuration for wider rollout.
