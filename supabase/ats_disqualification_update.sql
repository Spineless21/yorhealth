-- Add application-level disqualification fields for the ATS.
--
-- Disqualification belongs to the application, not the candidate, because a
-- candidate can be unsuitable for one vacancy and still valid for another.

alter table public.ats_applications
add column if not exists disqualified_at timestamptz,
add column if not exists disqualified_by text,
add column if not exists disqualification_reason text,
add column if not exists disqualification_notes text,
add column if not exists disqualification_source text,
add column if not exists disqualification_metadata jsonb not null default '{}'::jsonb;

create index if not exists ix_ats_applications_disqualified_at
    on public.ats_applications (disqualified_at)
    where disqualified_at is not null;

create index if not exists ix_ats_applications_disqualified_by
    on public.ats_applications (disqualified_by)
    where disqualified_by is not null;

-- Verification:
--
-- select column_name, data_type
-- from information_schema.columns
-- where table_schema = 'public'
--   and table_name = 'ats_applications'
--   and column_name like 'disqual%'
-- order by ordinal_position;
