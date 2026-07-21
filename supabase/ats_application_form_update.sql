-- ATS application form field update.
--
-- Purpose:
-- Add the candidate/application fields needed by the public application form.
-- This is additive and safe to run after supabase/ats_initial_schema.sql.

begin;

alter table public.ats_candidates
    add column if not exists right_to_work_uk text,
    add column if not exists driving_licence text,
    add column if not exists access_to_vehicle text,
    add column if not exists relevant_experience text,
    add column if not exists latest_cv_document_id uuid,
    add column if not exists latest_cv_external_url text,
    add column if not exists latest_cv_file_name text;

alter table public.ats_applications
    add column if not exists bubble_application_id text,
    add column if not exists application_source text,
    add column if not exists recruiter_owner text,
    add column if not exists application_notes text,
    add column if not exists screening_snapshot jsonb not null default '{}'::jsonb;

alter table public.ats_candidate_documents
    add column if not exists bubble_file_id text;

insert into public.ats_onboarding_check_types (
    check_type_key,
    check_type_name,
    reporting_group,
    empower_checklist_type_identifier,
    default_required,
    sort_order,
    is_compliance_check,
    is_active
)
values (
    'cv',
    'CV',
    'Recruitment',
    null,
    false,
    5,
    false,
    true
)
on conflict (check_type_key) do update
set
    check_type_name = excluded.check_type_name,
    reporting_group = excluded.reporting_group,
    empower_checklist_type_identifier = excluded.empower_checklist_type_identifier,
    default_required = excluded.default_required,
    sort_order = excluded.sort_order,
    is_compliance_check = excluded.is_compliance_check,
    is_active = true,
    updated_at = now();

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'ats_candidates_right_to_work_uk_chk'
    ) then
        alter table public.ats_candidates
            add constraint ats_candidates_right_to_work_uk_chk
            check (
                right_to_work_uk is null
                or right_to_work_uk in ('yes', 'no', 'unknown', 'requires_sponsorship')
            );
    end if;

    if not exists (
        select 1
        from pg_constraint
        where conname = 'ats_candidates_driving_licence_chk'
    ) then
        alter table public.ats_candidates
            add constraint ats_candidates_driving_licence_chk
            check (
                driving_licence is null
                or driving_licence in ('yes', 'no', 'provisional', 'unknown')
            );
    end if;

    if not exists (
        select 1
        from pg_constraint
        where conname = 'ats_candidates_access_to_vehicle_chk'
    ) then
        alter table public.ats_candidates
            add constraint ats_candidates_access_to_vehicle_chk
            check (
                access_to_vehicle is null
                or access_to_vehicle in ('yes', 'no', 'sometimes', 'unknown')
            );
    end if;
end;
$$;

create unique index if not exists ux_ats_applications_bubble_application_id
    on public.ats_applications (bubble_application_id)
    where bubble_application_id is not null
      and archived_at is null;

create index if not exists ix_ats_applications_source
    on public.ats_applications (application_source);

create index if not exists ix_ats_candidates_right_to_work
    on public.ats_candidates (right_to_work_uk);

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'powerbi_reader') then
        grant select on table
            public.ats_candidates,
            public.ats_applications,
            public.ats_candidate_documents
        to powerbi_reader;
    end if;
end;
$$;

commit;

-- Verification:
--
-- select column_name, data_type
-- from information_schema.columns
-- where table_schema = 'public'
--   and table_name in ('ats_candidates', 'ats_applications', 'ats_candidate_documents')
--   and column_name in (
--       'right_to_work_uk',
--       'driving_licence',
--       'access_to_vehicle',
--       'relevant_experience',
--       'latest_cv_external_url',
--       'bubble_application_id',
--       'application_source',
--       'screening_snapshot',
--       'bubble_file_id'
--   )
-- order by table_name, column_name;
