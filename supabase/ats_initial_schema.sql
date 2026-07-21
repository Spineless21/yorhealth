-- Initial ATS schema for Bubble portal + Empower integration.
-- Safe to run in Supabase SQL Editor. This is additive and does not alter the
-- existing Empower compliance tables/views.

begin;

create extension if not exists pgcrypto;

create schema if not exists app_private;

create or replace function app_private.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create table if not exists public.ats_application_stages (
    stage_key text primary key,
    stage_name text not null,
    stage_order integer not null,
    is_terminal boolean not null default false,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint ats_application_stages_stage_key_chk
        check (stage_key = lower(stage_key) and stage_key !~ '[[:space:]]')
);

create table if not exists public.ats_onboarding_check_types (
    check_type_key text primary key,
    check_type_name text not null,
    reporting_group text not null,
    empower_checklist_type_identifier text,
    default_required boolean not null default false,
    sort_order integer not null default 100,
    is_compliance_check boolean not null default true,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint ats_onboarding_check_types_check_type_key_chk
        check (check_type_key = lower(check_type_key) and check_type_key !~ '[[:space:]]')
);

create table if not exists public.ats_candidates (
    id uuid primary key default gen_random_uuid(),
    bubble_user_id text,
    email text not null,
    first_name text,
    last_name text,
    preferred_name text,
    phone text,
    date_of_birth date,
    address_line_1 text,
    address_line_2 text,
    town text,
    county text,
    postcode text,
    country text default 'United Kingdom',
    latitude numeric(9, 6),
    longitude numeric(9, 6),
    source text,
    candidate_status text not null default 'new',
    right_to_work_required boolean not null default true,
    sponsorship_required boolean not null default false,
    dbs_required boolean not null default true,
    consent_to_process boolean not null default false,
    consent_given_at timestamptz,
    empower_user_identifier text,
    empower_carer_identifier text,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    archived_at timestamptz,
    constraint ats_candidates_email_not_blank_chk
        check (length(trim(email)) > 0),
    constraint ats_candidates_status_chk
        check (
            candidate_status in (
                'new',
                'invited',
                'registered',
                'applied',
                'screening',
                'onboarding',
                'ready_to_create_in_empower',
                'synced_to_empower',
                'active_in_empower',
                'withdrawn',
                'rejected',
                'archived'
            )
        )
);

create table if not exists public.ats_vacancies (
    id uuid primary key default gen_random_uuid(),
    vacancy_code text,
    title text not null,
    job_title text,
    region_name text,
    location_name text,
    employment_type text,
    status text not null default 'open',
    opened_at timestamptz not null default now(),
    closed_at timestamptz,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint ats_vacancies_status_chk
        check (status in ('draft', 'open', 'on_hold', 'closed', 'archived'))
);

create table if not exists public.ats_applications (
    id uuid primary key default gen_random_uuid(),
    candidate_id uuid not null references public.ats_candidates(id) on delete cascade,
    vacancy_id uuid references public.ats_vacancies(id) on delete set null,
    current_stage_key text references public.ats_application_stages(stage_key),
    application_status text not null default 'active',
    applied_at timestamptz not null default now(),
    submitted_at timestamptz,
    decided_at timestamptz,
    decision_reason text,
    disqualified_at timestamptz,
    disqualified_by text,
    disqualification_reason text,
    disqualification_notes text,
    disqualification_source text,
    disqualification_metadata jsonb not null default '{}'::jsonb,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    archived_at timestamptz,
    constraint ats_applications_status_chk
        check (application_status in ('draft', 'active', 'hired', 'rejected', 'withdrawn', 'archived'))
);

create table if not exists public.ats_onboarding_checks (
    id uuid primary key default gen_random_uuid(),
    candidate_id uuid not null references public.ats_candidates(id) on delete cascade,
    application_id uuid references public.ats_applications(id) on delete cascade,
    check_type_key text not null references public.ats_onboarding_check_types(check_type_key),
    status text not null default 'not_started',
    required boolean not null default true,
    requested_at timestamptz,
    due_at timestamptz,
    submitted_at timestamptz,
    verified_at timestamptz,
    verified_by text,
    rejected_at timestamptz,
    rejection_reason text,
    expires_on timestamptz,
    document_review_date timestamptz,
    empower_checklist_type_identifier text,
    empower_checklist_status text,
    last_synced_to_empower_at timestamptz,
    last_synced_from_empower_at timestamptz,
    is_active boolean not null default true,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint ats_onboarding_checks_status_chk
        check (
            status in (
                'not_started',
                'requested',
                'submitted',
                'in_review',
                'verified',
                'rejected',
                'expired',
                'not_required',
                'cancelled'
            )
        )
);

create table if not exists public.ats_candidate_documents (
    id uuid primary key default gen_random_uuid(),
    candidate_id uuid not null references public.ats_candidates(id) on delete cascade,
    application_id uuid references public.ats_applications(id) on delete set null,
    onboarding_check_id uuid references public.ats_onboarding_checks(id) on delete set null,
    document_type_key text references public.ats_onboarding_check_types(check_type_key),
    title text,
    storage_provider text not null default 'bubble',
    storage_bucket text,
    storage_path text,
    external_url text,
    empower_file_identifier text,
    file_name text,
    mime_type text,
    file_size_bytes bigint,
    document_status text not null default 'uploaded',
    uploaded_by_bubble_user_id text,
    uploaded_at timestamptz not null default now(),
    verified_at timestamptz,
    verified_by text,
    expires_on timestamptz,
    document_review_date timestamptz,
    rejection_reason text,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    archived_at timestamptz,
    constraint ats_candidate_documents_storage_provider_chk
        check (storage_provider in ('bubble', 'supabase', 'empower', 'external')),
    constraint ats_candidate_documents_status_chk
        check (document_status in ('uploaded', 'received', 'in_review', 'verified', 'rejected', 'expired', 'archived')),
    constraint ats_candidate_documents_location_chk
        check (
            storage_path is not null
            or external_url is not null
            or empower_file_identifier is not null
        )
);

create table if not exists public.ats_stage_history (
    id uuid primary key default gen_random_uuid(),
    candidate_id uuid not null references public.ats_candidates(id) on delete cascade,
    application_id uuid references public.ats_applications(id) on delete cascade,
    from_stage_key text references public.ats_application_stages(stage_key),
    to_stage_key text not null references public.ats_application_stages(stage_key),
    changed_by text,
    changed_at timestamptz not null default now(),
    reason text,
    metadata jsonb not null default '{}'::jsonb
);

create table if not exists public.ats_notes (
    id uuid primary key default gen_random_uuid(),
    candidate_id uuid not null references public.ats_candidates(id) on delete cascade,
    application_id uuid references public.ats_applications(id) on delete cascade,
    note_type text not null default 'general',
    body text not null,
    visibility text not null default 'internal',
    created_by text,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint ats_notes_visibility_chk
        check (visibility in ('internal', 'candidate'))
);

create table if not exists public.ats_empower_entity_map (
    id uuid primary key default gen_random_uuid(),
    candidate_id uuid not null references public.ats_candidates(id) on delete cascade,
    bubble_user_id text,
    empower_user_identifier text,
    empower_carer_identifier text,
    empower_client_identifier text,
    sync_status text not null default 'not_synced',
    last_push_to_empower_at timestamptz,
    last_pull_from_empower_at timestamptz,
    last_successful_sync_at timestamptz,
    last_error text,
    raw_empower_user jsonb,
    raw_empower_carer jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint ats_empower_entity_map_status_chk
        check (sync_status in ('not_synced', 'pending', 'synced', 'failed', 'ignored'))
);

create table if not exists public.ats_sync_queue (
    id uuid primary key default gen_random_uuid(),
    source_system text not null,
    target_system text not null,
    direction text not null,
    entity_type text not null,
    entity_id uuid,
    external_identifier text,
    action text not null,
    status text not null default 'pending',
    priority integer not null default 100,
    attempts integer not null default 0,
    max_attempts integer not null default 5,
    next_attempt_at timestamptz not null default now(),
    locked_at timestamptz,
    locked_by text,
    processed_at timestamptz,
    payload jsonb not null default '{}'::jsonb,
    last_error text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint ats_sync_queue_direction_chk
        check (direction in ('bubble_to_supabase', 'supabase_to_empower', 'empower_to_supabase')),
    constraint ats_sync_queue_status_chk
        check (status in ('pending', 'processing', 'succeeded', 'failed', 'cancelled'))
);

create table if not exists public.ats_integration_events (
    id uuid primary key default gen_random_uuid(),
    source_system text not null,
    event_type text not null,
    external_event_id text,
    entity_type text,
    entity_id uuid,
    payload jsonb not null default '{}'::jsonb,
    status text not null default 'received',
    received_at timestamptz not null default now(),
    processed_at timestamptz,
    error text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint ats_integration_events_status_chk
        check (status in ('received', 'ignored', 'processed', 'failed'))
);

insert into public.ats_application_stages (stage_key, stage_name, stage_order, is_terminal)
values
    ('new', 'New', 10, false),
    ('reviewing', 'Reviewing', 20, false),
    ('contacting', 'Contacting', 30, false),
    ('interviewing', 'Interviewing', 40, false),
    ('rejected', 'Rejected', 50, true),
    ('hired', 'Hired', 60, true),
    ('withdrawn', 'Withdrawn', 70, true),
    ('onboarding', 'Onboarding', 80, false)
on conflict (stage_key) do update
set
    stage_name = excluded.stage_name,
    stage_order = excluded.stage_order,
    is_terminal = excluded.is_terminal,
    is_active = true,
    updated_at = now();

insert into public.ats_onboarding_check_types (
    check_type_key,
    check_type_name,
    reporting_group,
    empower_checklist_type_identifier,
    default_required,
    sort_order,
    is_compliance_check
)
values
    ('dbs', 'DBS', 'DBS', '1', true, 10, true),
    ('right_to_work', 'Right to Work', 'Right to Work', '2', true, 20, true),
    ('sponsorship', 'Sponsorship', 'Sponsorship', null, false, 30, true),
    ('identity', 'Identity', 'Identity', null, true, 40, true),
    ('references', 'References', 'References', null, true, 50, false),
    ('training', 'Training', 'Training', null, false, 60, false),
    ('contract', 'Contract', 'Contract', null, true, 70, false),
    ('other', 'Other', 'Other', null, false, 999, false)
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

create unique index if not exists ux_ats_candidates_email_lower
    on public.ats_candidates (lower(email))
    where archived_at is null;

create unique index if not exists ux_ats_candidates_bubble_user_id
    on public.ats_candidates (bubble_user_id)
    where bubble_user_id is not null and archived_at is null;

create index if not exists ix_ats_candidates_status
    on public.ats_candidates (candidate_status);

create index if not exists ix_ats_candidates_empower_user
    on public.ats_candidates (empower_user_identifier)
    where empower_user_identifier is not null;

create index if not exists ix_ats_candidates_empower_carer
    on public.ats_candidates (empower_carer_identifier)
    where empower_carer_identifier is not null;

create unique index if not exists ux_ats_vacancies_code
    on public.ats_vacancies (vacancy_code)
    where vacancy_code is not null;

create index if not exists ix_ats_vacancies_status
    on public.ats_vacancies (status);

create index if not exists ix_ats_applications_candidate
    on public.ats_applications (candidate_id);

create index if not exists ix_ats_applications_vacancy
    on public.ats_applications (vacancy_id);

create index if not exists ix_ats_applications_stage
    on public.ats_applications (current_stage_key);

create unique index if not exists ux_ats_applications_candidate_vacancy_active
    on public.ats_applications (candidate_id, vacancy_id)
    where vacancy_id is not null and archived_at is null;

create index if not exists ix_ats_onboarding_checks_candidate
    on public.ats_onboarding_checks (candidate_id);

create index if not exists ix_ats_onboarding_checks_application
    on public.ats_onboarding_checks (application_id);

create index if not exists ix_ats_onboarding_checks_status
    on public.ats_onboarding_checks (status);

create unique index if not exists ux_ats_onboarding_checks_active_type
    on public.ats_onboarding_checks (
        candidate_id,
        coalesce(application_id, '00000000-0000-0000-0000-000000000000'::uuid),
        check_type_key
    )
    where is_active = true;

create index if not exists ix_ats_candidate_documents_candidate
    on public.ats_candidate_documents (candidate_id);

create index if not exists ix_ats_candidate_documents_check
    on public.ats_candidate_documents (onboarding_check_id);

create index if not exists ix_ats_candidate_documents_status
    on public.ats_candidate_documents (document_status);

create index if not exists ix_ats_stage_history_candidate
    on public.ats_stage_history (candidate_id, changed_at desc);

create index if not exists ix_ats_notes_candidate
    on public.ats_notes (candidate_id, created_at desc)
    where deleted_at is null;

create unique index if not exists ux_ats_empower_entity_map_candidate
    on public.ats_empower_entity_map (candidate_id);

create unique index if not exists ux_ats_empower_entity_map_user
    on public.ats_empower_entity_map (empower_user_identifier)
    where empower_user_identifier is not null;

create unique index if not exists ux_ats_empower_entity_map_carer
    on public.ats_empower_entity_map (empower_carer_identifier)
    where empower_carer_identifier is not null;

create index if not exists ix_ats_sync_queue_pending
    on public.ats_sync_queue (status, next_attempt_at, priority)
    where status in ('pending', 'failed');

create index if not exists ix_ats_sync_queue_entity
    on public.ats_sync_queue (entity_type, entity_id);

create unique index if not exists ux_ats_integration_events_external_event
    on public.ats_integration_events (source_system, external_event_id)
    where external_event_id is not null;

create index if not exists ix_ats_integration_events_status
    on public.ats_integration_events (status, received_at);

drop trigger if exists trg_ats_application_stages_updated_at on public.ats_application_stages;
create trigger trg_ats_application_stages_updated_at
before update on public.ats_application_stages
for each row execute function app_private.set_updated_at();

drop trigger if exists trg_ats_onboarding_check_types_updated_at on public.ats_onboarding_check_types;
create trigger trg_ats_onboarding_check_types_updated_at
before update on public.ats_onboarding_check_types
for each row execute function app_private.set_updated_at();

drop trigger if exists trg_ats_candidates_updated_at on public.ats_candidates;
create trigger trg_ats_candidates_updated_at
before update on public.ats_candidates
for each row execute function app_private.set_updated_at();

drop trigger if exists trg_ats_vacancies_updated_at on public.ats_vacancies;
create trigger trg_ats_vacancies_updated_at
before update on public.ats_vacancies
for each row execute function app_private.set_updated_at();

drop trigger if exists trg_ats_applications_updated_at on public.ats_applications;
create trigger trg_ats_applications_updated_at
before update on public.ats_applications
for each row execute function app_private.set_updated_at();

drop trigger if exists trg_ats_onboarding_checks_updated_at on public.ats_onboarding_checks;
create trigger trg_ats_onboarding_checks_updated_at
before update on public.ats_onboarding_checks
for each row execute function app_private.set_updated_at();

drop trigger if exists trg_ats_candidate_documents_updated_at on public.ats_candidate_documents;
create trigger trg_ats_candidate_documents_updated_at
before update on public.ats_candidate_documents
for each row execute function app_private.set_updated_at();

drop trigger if exists trg_ats_notes_updated_at on public.ats_notes;
create trigger trg_ats_notes_updated_at
before update on public.ats_notes
for each row execute function app_private.set_updated_at();

drop trigger if exists trg_ats_empower_entity_map_updated_at on public.ats_empower_entity_map;
create trigger trg_ats_empower_entity_map_updated_at
before update on public.ats_empower_entity_map
for each row execute function app_private.set_updated_at();

drop trigger if exists trg_ats_sync_queue_updated_at on public.ats_sync_queue;
create trigger trg_ats_sync_queue_updated_at
before update on public.ats_sync_queue
for each row execute function app_private.set_updated_at();

drop trigger if exists trg_ats_integration_events_updated_at on public.ats_integration_events;
create trigger trg_ats_integration_events_updated_at
before update on public.ats_integration_events
for each row execute function app_private.set_updated_at();

alter table public.ats_application_stages enable row level security;
alter table public.ats_onboarding_check_types enable row level security;
alter table public.ats_candidates enable row level security;
alter table public.ats_vacancies enable row level security;
alter table public.ats_applications enable row level security;
alter table public.ats_onboarding_checks enable row level security;
alter table public.ats_candidate_documents enable row level security;
alter table public.ats_stage_history enable row level security;
alter table public.ats_notes enable row level security;
alter table public.ats_empower_entity_map enable row level security;
alter table public.ats_sync_queue enable row level security;
alter table public.ats_integration_events enable row level security;

revoke all on table
    public.ats_application_stages,
    public.ats_onboarding_check_types,
    public.ats_candidates,
    public.ats_vacancies,
    public.ats_applications,
    public.ats_onboarding_checks,
    public.ats_candidate_documents,
    public.ats_stage_history,
    public.ats_notes,
    public.ats_empower_entity_map,
    public.ats_sync_queue,
    public.ats_integration_events
from anon, authenticated;

create or replace view public.v_ats_candidate_onboarding_status
with (security_invoker = true)
as
select
    c.id as candidate_id,
    c.bubble_user_id,
    c.email,
    c.first_name,
    c.last_name,
    nullif(trim(concat_ws(' ', c.first_name, c.last_name)), '') as candidate_name,
    c.phone,
    c.town,
    c.postcode,
    c.latitude,
    c.longitude,
    c.candidate_status,
    c.empower_user_identifier,
    c.empower_carer_identifier,
    count(ch.id) filter (where ch.is_active = true and ch.required = true) as required_checks,
    count(ch.id) filter (
        where ch.is_active = true
          and ch.required = true
          and ch.status = 'verified'
    ) as verified_checks,
    count(ch.id) filter (
        where ch.is_active = true
          and ch.required = true
          and ch.status in ('not_started', 'requested', 'submitted', 'in_review', 'rejected')
    ) as outstanding_checks,
    count(ch.id) filter (
        where ch.is_active = true
          and ch.required = true
          and (
              ch.status = 'expired'
              or ch.expires_on::date < current_date
          )
    ) as expired_checks,
    count(ch.id) filter (
        where ch.is_active = true
          and ch.required = true
          and ch.status = 'verified'
          and ch.expires_on is not null
          and ch.expires_on::date >= current_date
          and ch.expires_on::date <= current_date + interval '30 days'
    ) as warning_checks,
    case
        when count(ch.id) filter (
            where ch.is_active = true
              and ch.required = true
              and (
                  ch.status = 'expired'
                  or ch.expires_on::date < current_date
              )
        ) > 0 then 'Expired'
        when count(ch.id) filter (
            where ch.is_active = true
              and ch.required = true
              and ch.status in ('not_started', 'requested', 'submitted', 'in_review', 'rejected')
        ) > 0 then 'Outstanding'
        when count(ch.id) filter (
            where ch.is_active = true
              and ch.required = true
              and ch.status = 'verified'
              and ch.expires_on is not null
              and ch.expires_on::date >= current_date
              and ch.expires_on::date <= current_date + interval '30 days'
        ) > 0 then 'Warning'
        else 'Compliant'
    end as onboarding_status,
    c.created_at,
    c.updated_at
from public.ats_candidates c
left join public.ats_onboarding_checks ch
    on c.id = ch.candidate_id
where c.archived_at is null
group by
    c.id,
    c.bubble_user_id,
    c.email,
    c.first_name,
    c.last_name,
    c.phone,
    c.town,
    c.postcode,
    c.latitude,
    c.longitude,
    c.candidate_status,
    c.empower_user_identifier,
    c.empower_carer_identifier,
    c.created_at,
    c.updated_at;

revoke all on table public.v_ats_candidate_onboarding_status from anon, authenticated;

comment on table public.ats_candidates is
    'Candidate master record for the internal ATS. Bubble login records should store/reference ats_candidates.id via bubble_user_id.';

comment on table public.ats_sync_queue is
    'Outbox queue for controlled sync between Bubble, Supabase and Empower. Process with an Edge Function or scheduled worker.';

comment on table public.ats_integration_events is
    'Inbound webhook/API event log for Empower or Bubble events before/after processing.';

commit;

-- Verification queries to run after the migration:
-- select table_name
-- from information_schema.tables
-- where table_schema = 'public'
--   and table_name like 'ats_%'
-- order by table_name;
--
-- select check_type_key, check_type_name, reporting_group
-- from public.ats_onboarding_check_types
-- order by sort_order;
--
-- select stage_key, stage_name, stage_order
-- from public.ats_application_stages
-- order by stage_order;
