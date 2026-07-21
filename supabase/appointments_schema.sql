-- Empower appointments/shifts schema for compliance reporting.
--
-- Purpose:
-- Store appointment data from the Empower/Nourish Appointments API so the
-- compliance dashboard can tell whether a carer has booked shifts.
--
-- This supports the business rule:
-- If a carer has never uploaded a certain document and has no booked shifts,
-- show the checklist item as Pending instead of Non-Compliant/Outstanding.

begin;

create table if not exists public.appointments_raw (
    appointment_identifier text primary key,
    payload jsonb not null,
    range_start timestamptz,
    range_end timestamptz,
    last_updated timestamptz,
    synced_at timestamptz not null default now(),
    is_active boolean not null default true
);

create table if not exists public.appointments (
    appointment_identifier text primary key,
    internal_identifier bigint,
    version integer,
    client_identifier text,
    appointment_preset integer,
    start_at timestamptz,
    end_at timestamptz,
    timezone text,
    status text,
    cancelled boolean not null default false,
    deleted boolean not null default false,
    last_updated timestamptz,
    payload jsonb not null default '{}'::jsonb,
    synced_at timestamptz not null default now(),
    is_active boolean not null default true
);

create table if not exists public.appointment_carers (
    appointment_carer_key text primary key,
    appointment_identifier text not null references public.appointments(appointment_identifier) on delete cascade,
    slot_identifier text,
    carer_identifier text,
    slot integer,
    run_identifier text,
    required boolean,
    start_at timestamptz,
    end_at timestamptz,
    status text,
    cancelled boolean not null default false,
    deleted boolean not null default false,
    payload jsonb not null default '{}'::jsonb,
    synced_at timestamptz not null default now(),
    is_active boolean not null default true
);

create unique index if not exists ux_appointment_carers_slot
    on public.appointment_carers (
        appointment_identifier,
        coalesce(slot_identifier, ''),
        coalesce(carer_identifier, ''),
        coalesce(slot, -1)
    );

create index if not exists ix_appointments_start_at
    on public.appointments (start_at);

create index if not exists ix_appointments_active_future
    on public.appointments (start_at, appointment_identifier)
    where is_active = true
      and cancelled = false
      and deleted = false;

create index if not exists ix_appointment_carers_carer
    on public.appointment_carers (carer_identifier);

create index if not exists ix_appointment_carers_carer_future
    on public.appointment_carers (carer_identifier, start_at)
    where is_active = true
      and cancelled = false
      and deleted = false;

create or replace view public.v_carer_shift_activity
with (security_invoker = true)
as
select
    ac.carer_identifier as carer_id,
    min(ac.start_at) filter (
        where ac.start_at >= current_date
          and ac.is_active = true
          and ac.cancelled = false
          and ac.deleted = false
    ) as next_shift_start_at,
    count(*) filter (
        where ac.start_at >= current_date
          and ac.is_active = true
          and ac.cancelled = false
          and ac.deleted = false
    ) as future_booked_shift_count,
    count(*) filter (
        where ac.start_at < current_date
          and ac.is_active = true
          and ac.cancelled = false
          and ac.deleted = false
    ) as historic_shift_count,
    max(ac.start_at) filter (
        where ac.start_at < current_date
          and ac.is_active = true
          and ac.cancelled = false
          and ac.deleted = false
    ) as last_shift_start_at
from public.appointment_carers ac
where ac.carer_identifier is not null
group by ac.carer_identifier;

commit;

-- Verification once appointment data is synced:
--
-- select count(*) from public.appointments;
-- select count(*) from public.appointment_carers;
-- select * from public.v_carer_shift_activity order by future_booked_shift_count desc limit 20;
