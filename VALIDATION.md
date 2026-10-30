# Initial validation — 30 October 2026

Supabase schema installed successfully in the selected project. `database/verify.sql` passed against PostgreSQL with transaction-local fixtures and rollback. It checked active-staff reads, an assigned technician's update, version increments, appended actor history, stale-write rejection, assignment and closure restrictions, direct-update denial, unrelated technician write denial, inactive-member read denial, and anonymous read denial. No test accounts or tickets were retained.

Browser demo checks passed: create and assign a ticket; reload and retain the ticket; add a work-activity note; record a material; search for the ticket; reject closure without a resolution; close with a resolution and customer feedback; update overview counts. An observed validation-message visibility issue was fixed by showing feedback inside the open dialog.

The shared project URL and publishable key were verified. New public signups are disabled, anonymous sign-in remains disabled, and the authentication Site URL and exact redirect URL point to the GitHub Pages site.

Staff invitation delivery and the first recipient's password setup require the recipient. No passwords were generated, handled or stored by the builder. Additional staff provisioning and end-user acceptance should follow before operational rollout. Automated messaging, attachments, stock control and formal SLA automation are outside this release.

## Legacy continuity update

Applied the incremental legacy-provenance migration and passed the existing permission suite plus `database/verify_legacy.sql`. The new tests verify that a manager can continue an imported ticket with an unknown original date and an unprovisioned historical assignee, while new invalid assignments, date-free new tickets, and attempted provenance changes remain rejected. All test fixtures roll back. A fictional browser fixture verified the original-source panel, original assignee selection, unknown-date display, adding a new work note, and saving a priority change while retaining source fields. Private workbook extracts and customer import statements are excluded from repository source.

## Unique Energy and team access update

Renamed the interface and added separate Tech, Manager, Ticket report, Lists and Team access areas. Source reconciliation matched all original directory fields and every dropdown/catalogue value, including automatic ticket-selection IDs. The two historical tickets and technical activities remain in protected storage. The manager register had no submitted updates; unsubmitted form values were not imported.

The original permissions and legacy regression tests and the new Energy access suite passed with rollback-only fictional fixtures. The access suite checks an authenticated outsider with no approved profile, direct self-approval, non-admin promotion/listing, admin self-removal protection, member approval and deactivation, private audit visibility, and anonymous denial. Public Auth settings report signup disabled, anonymous users disabled and social providers disabled. The invitation function returns 401 for missing or invalid sessions. The browser demo verified technical and manager submissions and their appearance in the generated report; the latest demo uses fictional staff names. Recipient password setup and real in-app mail delivery require an approved operator's session; no test invitations were sent to unrelated people.
