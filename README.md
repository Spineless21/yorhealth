# YorHealth Data and ATS Integrations

This repository is a working record of the internal data and recruitment automation build.

It contains the Supabase SQL, Edge Functions, documentation, and prototype front-end files used to support:

- Empower/Nourish data sync into Supabase
- Power BI compliance and timesheet reporting
- Bubble ATS integration with Supabase
- Microsoft Graph email and interview scheduling for the ATS
- Careers page and candidate portal mockups

## Main Areas

### Supabase

`supabase/`

Contains database setup SQL, reporting views, scheduled sync SQL, and Edge Functions.

Key functions:

- `supabase/functions/ats-portal-api/index.ts`
- `supabase/functions/ats-graph-api/index.ts`
- `supabase/functions/sync-nourish-appointments/index.ts`
- `supabase/functions/sync-nourish-timesheets/index.ts`

### Documentation

`docs/`

Contains the living ATS build documentation and Bubble/Supabase API setup notes.

Key files:

- `docs/ats-build-documentation.md`
- `docs/bubble-supabase-ats-api-setup.md`
- `docs/supabase-empower-compliance-documentation.md`

### ATS Mockups

Root HTML files contain prototype screens for the careers page, candidate signup, candidate login, and candidate portal.

Key files:

- `careers-page-mockup.html`
- `careers-job.html`
- `candidate-signup.html`
- `candidate-login.html`
- `candidate-portal.html`
- `yorlink-ats-mockup.html`

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
