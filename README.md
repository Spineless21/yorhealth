# YorHealth Data and ATS Integrations

This repository is a working source snapshot of the internal data and recruitment automation build.

It currently focuses on the backend/source-of-truth code used to support:

- Empower/Nourish data sync into Supabase
- Power BI compliance and timesheet reporting
- Bubble ATS integration with Supabase
- Microsoft Graph email and interview scheduling for the ATS

## Main Areas

### Supabase SQL

`supabase/`

Contains database setup SQL, reporting views, scheduled sync SQL, RLS support, appointment sync setup, timesheet reporting setup, ATS schema updates, and compliance view updates.

### Edge Functions

Key functions committed as readable source:

- `supabase/functions/ats-portal-api/index.ts`
- `supabase/functions/sync-nourish-appointments/index.ts`
- `supabase/functions/sync-nourish-timesheets/index.ts`

The Microsoft Graph function is larger than the connector could safely upload as one UTF-8 file, so it is preserved as a recoverable base64 source snapshot here:

- `supabase/functions/ats-graph-api/README.md`
- `supabase/functions/ats-graph-api/index.ts.b64.part1`
- `supabase/functions/ats-graph-api/index.ts.b64.part2`
- `supabase/functions/ats-graph-api/index.ts.b64.part3`
- `supabase/functions/ats-graph-api/index.ts.b64.part4`

Follow the restore command in `supabase/functions/ats-graph-api/README.md` to recreate `index.ts` exactly from those four parts.

## Not Included

Generated documents, rendered previews, dependency folders, temporary files, and binary assets are intentionally not committed.

The local workspace also contains board documentation and HTML mockups. Those are useful artefacts, but the first GitHub pass keeps the repository centred on durable backend code and avoids committing generated/noisy files.

## Security Notes

Secrets are not stored in this repository.

Supabase Edge Functions expect secrets to be configured in Supabase, such as:

- `SUPABASE_SERVICE_ROLE_KEY`
- `BUBBLE_API_SECRET`
- `NOURISH_CLIENT_ID`
- `NOURISH_CLIENT_SECRET`
- `MS_TENANT_ID`
- `MS_CLIENT_ID`
- `MS_CLIENT_SECRET`
- `MS_RECRUITMENT_MAILBOX`
- `MS_RECRUITMENT_USER_ID`

## Current Status

Working integrations include:

- Bubble candidate/application/vacancy sync to Supabase
- ATS email sending through Microsoft Graph
- ATS interview creation through Microsoft Graph
- Teams meeting link generation for recruitment interviews
- Nourish appointment and timesheet sync into Supabase
- Power BI reporting views for compliance and hours
