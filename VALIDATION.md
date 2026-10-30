# Initial validation — 30 October 2026

Supabase schema installed successfully in the selected project. `database/verify.sql` passed against PostgreSQL with transaction-local fixtures and rollback. It checked active-staff reads, an assigned technician's update, version increments, appended actor history, stale-write rejection, assignment and closure restrictions, direct-update denial, unrelated technician write denial, inactive-member read denial, and anonymous read denial. No test accounts or tickets were retained.

Browser demo checks passed: create and assign a ticket; reload and retain the ticket; add a work-activity note; record a material; search for the ticket; reject closure without a resolution; close with a resolution and customer feedback; update overview counts. An observed validation-message visibility issue was fixed by showing feedback inside the open dialog.

The shared project URL and publishable key were verified. New public signups are disabled, anonymous sign-in remains disabled, and the authentication Site URL and exact redirect URL point to the GitHub Pages site.

Staff invitation delivery and the first recipient's password setup require the recipient. No passwords were generated, handled or stored by the builder. Additional staff provisioning and end-user acceptance should follow before operational rollout. Automated messaging, attachments, stock control and formal SLA automation are outside this release.
