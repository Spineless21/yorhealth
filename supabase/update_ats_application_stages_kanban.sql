-- Align ATS application stages with the Bubble kanban stage option set.
--
-- Active stages after this update:
-- new, reviewing, contacting, interviewing, rejected, hired, withdrawn, onboarding.
--
-- Old stages are marked inactive rather than deleted so historical foreign keys remain safe.

with mapped_applications as (
    update public.ats_applications
    set
        current_stage_key = case
            when current_stage_key in ('new', 'invited', 'application_started', 'application_submitted') then 'new'
            when current_stage_key in ('screening') then 'reviewing'
            when current_stage_key in ('interview') then 'interviewing'
            when current_stage_key in ('offer', 'onboarding', 'ready_for_empower', 'synced_to_empower') then 'onboarding'
            else current_stage_key
        end,
        updated_at = now()
    where current_stage_key in (
        'invited',
        'application_started',
        'application_submitted',
        'screening',
        'interview',
        'offer',
        'ready_for_empower',
        'synced_to_empower'
    )
    returning id
),
upsert_stages as (
    insert into public.ats_application_stages (
        stage_key,
        stage_name,
        stage_order,
        is_terminal,
        is_active
    )
    values
        ('new', 'New', 10, false, true),
        ('reviewing', 'Reviewing', 20, false, true),
        ('contacting', 'Contacting', 30, false, true),
        ('interviewing', 'Interviewing', 40, false, true),
        ('rejected', 'Rejected', 50, true, true),
        ('hired', 'Hired', 60, true, true),
        ('withdrawn', 'Withdrawn', 70, true, true),
        ('onboarding', 'Onboarding', 80, false, true)
    on conflict (stage_key) do update
    set
        stage_name = excluded.stage_name,
        stage_order = excluded.stage_order,
        is_terminal = excluded.is_terminal,
        is_active = excluded.is_active,
        updated_at = now()
    returning stage_key
),
inactive_old_stages as (
    update public.ats_application_stages
    set
        is_active = false,
        updated_at = now()
    where stage_key in (
        'invited',
        'application_started',
        'application_submitted',
        'screening',
        'interview',
        'offer',
        'ready_for_empower',
        'synced_to_empower'
    )
    returning stage_key
)
select
    (select count(*) from mapped_applications) as applications_remapped,
    (select count(*) from upsert_stages) as active_stages_upserted,
    (select count(*) from inactive_old_stages) as old_stages_marked_inactive;

-- Verification:
--
-- select stage_key, stage_name, stage_order, is_terminal, is_active
-- from public.ats_application_stages
-- order by is_active desc, stage_order, stage_key;
--
-- select current_stage_key, count(*) as applications
-- from public.ats_applications
-- group by current_stage_key
-- order by current_stage_key;
