-- ATS population examples.
--
-- Use this after running supabase/ats_initial_schema.sql.
-- These examples show the order data should be created in:
-- 1. vacancy
-- 2. candidate from Bubble user
-- 3. application
-- 4. onboarding checks
-- 5. documents
-- 6. sync queue item for Empower

begin;

-- 1) Create a vacancy/role that candidates can apply for.
insert into public.ats_vacancies (
    vacancy_code,
    title,
    job_title,
    region_name,
    location_name,
    employment_type,
    status
)
values (
    'SW-MID-001',
    'Support Worker - Midlands',
    'Support Worker',
    'SL - Midlands',
    'Midlands',
    'Permanent',
    'open'
)
on conflict (vacancy_code) do update
set
    title = excluded.title,
    job_title = excluded.job_title,
    region_name = excluded.region_name,
    location_name = excluded.location_name,
    employment_type = excluded.employment_type,
    status = excluded.status,
    updated_at = now();

-- 2) Create/update a candidate when a Bubble portal user registers.
--    Bubble should store the returned ats_candidates.id against the Bubble user.
insert into public.ats_candidates (
    bubble_user_id,
    email,
    first_name,
    last_name,
    phone,
    postcode,
    source,
    candidate_status,
    consent_to_process,
    consent_given_at,
    sponsorship_required
)
values (
    'bubble_user_123',
    'example.candidate@example.com',
    'Example',
    'Candidate',
    '07123456789',
    'B1 1AA',
    'Bubble portal',
    'registered',
    true,
    now(),
    false
)
on conflict (lower(email)) where archived_at is null do update
set
    bubble_user_id = excluded.bubble_user_id,
    first_name = excluded.first_name,
    last_name = excluded.last_name,
    phone = excluded.phone,
    postcode = excluded.postcode,
    candidate_status = excluded.candidate_status,
    consent_to_process = excluded.consent_to_process,
    consent_given_at = excluded.consent_given_at,
    updated_at = now();

-- 3) Create an application for that candidate.
insert into public.ats_applications (
    candidate_id,
    vacancy_id,
    current_stage_key,
    application_status,
    applied_at,
    submitted_at
)
select
    c.id,
    v.id,
    'application_submitted',
    'active',
    now(),
    now()
from public.ats_candidates c
join public.ats_vacancies v
    on v.vacancy_code = 'SW-MID-001'
where lower(c.email) = lower('example.candidate@example.com')
on conflict (candidate_id, vacancy_id) where archived_at is null do update
set
    current_stage_key = excluded.current_stage_key,
    application_status = excluded.application_status,
    submitted_at = coalesce(public.ats_applications.submitted_at, excluded.submitted_at),
    updated_at = now();

-- 4) Create default onboarding checks.
--    This creates DBS, Right to Work, Identity, References and Contract.
--    Sponsorship is only created when candidate.sponsorship_required = true.
insert into public.ats_onboarding_checks (
    candidate_id,
    application_id,
    check_type_key,
    status,
    required,
    requested_at,
    due_at
)
select
    c.id,
    a.id,
    oct.check_type_key,
    'requested',
    true,
    now(),
    now() + interval '14 days'
from public.ats_candidates c
join public.ats_applications a
    on a.candidate_id = c.id
join public.ats_onboarding_check_types oct
    on oct.check_type_key in ('dbs', 'right_to_work', 'identity', 'references', 'contract')
where lower(c.email) = lower('example.candidate@example.com')
  and oct.is_active = true
on conflict (
    candidate_id,
    coalesce(application_id, '00000000-0000-0000-0000-000000000000'::uuid),
    check_type_key
)
where is_active = true do nothing;

insert into public.ats_onboarding_checks (
    candidate_id,
    application_id,
    check_type_key,
    status,
    required,
    requested_at,
    due_at
)
select
    c.id,
    a.id,
    'sponsorship',
    'requested',
    true,
    now(),
    now() + interval '14 days'
from public.ats_candidates c
join public.ats_applications a
    on a.candidate_id = c.id
where lower(c.email) = lower('example.candidate@example.com')
  and c.sponsorship_required = true
on conflict (
    candidate_id,
    coalesce(application_id, '00000000-0000-0000-0000-000000000000'::uuid),
    check_type_key
)
where is_active = true do nothing;

-- 5) When Bubble receives an uploaded document, insert metadata here.
--    Use external_url for Bubble-hosted files, or storage_path for Supabase Storage.
insert into public.ats_candidate_documents (
    candidate_id,
    application_id,
    onboarding_check_id,
    document_type_key,
    title,
    storage_provider,
    external_url,
    file_name,
    mime_type,
    document_status,
    uploaded_by_bubble_user_id,
    uploaded_at
)
select
    c.id,
    a.id,
    ch.id,
    'right_to_work',
    'Right to Work Upload',
    'bubble',
    'https://example.com/replace-with-bubble-file-url',
    'right-to-work.pdf',
    'application/pdf',
    'uploaded',
    c.bubble_user_id,
    now()
from public.ats_candidates c
join public.ats_applications a
    on a.candidate_id = c.id
join public.ats_onboarding_checks ch
    on ch.candidate_id = c.id
   and ch.application_id = a.id
   and ch.check_type_key = 'right_to_work'
where lower(c.email) = lower('example.candidate@example.com');

-- 6) Queue the candidate for a future Empower sync once internal review is done.
insert into public.ats_sync_queue (
    source_system,
    target_system,
    direction,
    entity_type,
    entity_id,
    action,
    status,
    payload
)
select
    'supabase',
    'empower',
    'supabase_to_empower',
    'candidate',
    c.id,
    'create_or_update_worker',
    'pending',
    jsonb_build_object(
        'candidate_id', c.id,
        'email', c.email,
        'bubble_user_id', c.bubble_user_id
    )
from public.ats_candidates c
where lower(c.email) = lower('example.candidate@example.com');

commit;

-- Useful checks:
--
-- select * from public.v_ats_candidate_onboarding_status;
--
-- select
--     c.email,
--     ch.check_type_key,
--     ch.status,
--     ch.due_at,
--     ch.expires_on
-- from public.ats_candidates c
-- join public.ats_onboarding_checks ch
--     on ch.candidate_id = c.id
-- order by c.created_at desc, ch.created_at;
