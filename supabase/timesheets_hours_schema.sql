-- Empower/Nourish timesheets schema for weekly true hours reporting.
--
-- Purpose:
-- Store finance timesheet data from Empower so Power BI can report true weekly
-- hours using timesheet line items, including breaks and overnight shifts.
--
-- Key reporting rule:
-- A shift is assigned to the week in which the shift starts. A Sunday night
-- shift that runs into Monday is counted in full against the week containing
-- that Sunday; it is not split at midnight.
--
-- Required Empower API scopes:
--   timesheet_read
--   user_carer_read
--   region_read
--
-- Recommended optional scopes:
--   appointment_read
--   user_client_read
--   actual_time_reason_read

begin;

create table if not exists public.timesheet_sync_runs (
    id bigserial primary key,
    started_at timestamptz not null default now(),
    finished_at timestamptz,
    status text not null default 'running',
    requested_start_date date,
    requested_end_date date,
    timesheets_seen integer not null default 0,
    timesheets_upserted integer not null default 0,
    line_items_upserted integer not null default 0,
    extra_items_upserted integer not null default 0,
    error_message text,
    metadata jsonb not null default '{}'::jsonb
);

create table if not exists public.timesheets_raw (
    timesheet_identifier text primary key,
    payload jsonb not null,
    period_start date,
    period_end date,
    issued_date date,
    paid_status text,
    carer_identifier text,
    synced_at timestamptz not null default now(),
    sync_run_id bigint references public.timesheet_sync_runs(id) on delete set null,
    is_active boolean not null default true
);

create table if not exists public.timesheets (
    timesheet_identifier text primary key,
    carer_identifier text,
    payment_group text,
    period_start date,
    period_end date,
    issued_date date,
    paid_status text,
    regions jsonb not null default '[]'::jsonb,
    all_regions boolean,
    formatted_timesheet_number text,
    address text,
    carer_max_hours integer,
    carer_payroll_number text,
    total_cost numeric(12, 2),
    totals jsonb not null default '{}'::jsonb,
    metadata jsonb not null default '{}'::jsonb,
    payload jsonb not null default '{}'::jsonb,
    synced_at timestamptz not null default now(),
    sync_run_id bigint references public.timesheet_sync_runs(id) on delete set null,
    is_active boolean not null default true
);

create table if not exists public.timesheet_line_items (
    line_item_key text primary key,
    timesheet_identifier text not null references public.timesheets(timesheet_identifier) on delete cascade,
    line_item_index integer not null,
    line_type text,
    entity_identifier text,
    client_identifier text,
    rate_identifier text,
    version integer,
    cancelled boolean not null default false,
    start_at timestamptz,
    end_at timestamptz,
    rate_of_pay numeric(12, 4),
    rate_description text,
    rate_name text,
    cost numeric(12, 2),
    client_mileage_cost numeric(12, 2),
    client_mileage_distance numeric(12, 2),
    travel_mileage_cost numeric(12, 2),
    travel_mileage_distance numeric(12, 2),
    travel_time_cost numeric(12, 2),
    travel_time_minutes integer,
    waiting_time_cost numeric(12, 2),
    waiting_time_minutes integer,
    cancellation_fee integer,
    break_time_minutes integer,
    duration_minutes integer,
    booking_reference text,
    payload jsonb not null default '{}'::jsonb,
    synced_at timestamptz not null default now(),
    sync_run_id bigint references public.timesheet_sync_runs(id) on delete set null,
    is_active boolean not null default true
);

create table if not exists public.timesheet_extra_items (
    extra_item_key text primary key,
    timesheet_identifier text not null references public.timesheets(timesheet_identifier) on delete cascade,
    extra_item_index integer not null,
    description text,
    cost numeric(12, 2),
    payload jsonb not null default '{}'::jsonb,
    synced_at timestamptz not null default now(),
    sync_run_id bigint references public.timesheet_sync_runs(id) on delete set null,
    is_active boolean not null default true
);

create unique index if not exists ux_timesheet_line_items_position
    on public.timesheet_line_items (timesheet_identifier, line_item_index);

create unique index if not exists ux_timesheet_extra_items_position
    on public.timesheet_extra_items (timesheet_identifier, extra_item_index);

create index if not exists ix_timesheets_carer_period
    on public.timesheets (carer_identifier, period_start, period_end);

create index if not exists ix_timesheets_period
    on public.timesheets (period_start, period_end);

create index if not exists ix_timesheet_line_items_timesheet
    on public.timesheet_line_items (timesheet_identifier);

create index if not exists ix_timesheet_line_items_carer_start
    on public.timesheet_line_items (start_at, timesheet_identifier)
    where is_active = true
      and cancelled = false;

create index if not exists ix_timesheet_line_items_entity
    on public.timesheet_line_items (entity_identifier)
    where entity_identifier is not null;

create index if not exists ix_timesheet_line_items_client
    on public.timesheet_line_items (client_identifier)
    where client_identifier is not null;

create or replace view public.v_timesheet_line_item_hours
with (security_invoker = true)
as
select
    li.line_item_key,
    li.timesheet_identifier,
    li.line_item_index,
    ts.formatted_timesheet_number,
    ts.carer_identifier,
    c.full_name as carer_name,
    c.primary_region_name,
    ts.carer_payroll_number,
    ts.period_start as timesheet_period_start,
    ts.period_end as timesheet_period_end,
    ts.paid_status,
    li.line_type,
    li.entity_identifier as appointment_identifier,
    li.client_identifier,
    li.rate_identifier,
    li.rate_name,
    li.rate_description,
    li.booking_reference,
    li.cancelled,
    li.start_at,
    li.end_at,
    (li.start_at at time zone 'Europe/London') as local_start_at,
    (li.end_at at time zone 'Europe/London') as local_end_at,
    date_trunc('week', li.start_at at time zone 'Europe/London')::date as week_start_date,
    (date_trunc('week', li.start_at at time zone 'Europe/London')::date + 6) as week_end_date,
    extract(isodow from li.start_at at time zone 'Europe/London') = 7 as starts_on_sunday,
    (li.start_at at time zone 'Europe/London')::date <> (li.end_at at time zone 'Europe/London')::date as crosses_midnight,
    li.break_time_minutes,
    round((coalesce(li.break_time_minutes, 0)::numeric / 3600), 2) as break_hours,
    li.duration_minutes,
    round(
        greatest(
            extract(epoch from (li.end_at - li.start_at)) / 3600,
            0
        )::numeric,
        2
    ) as gross_hours_from_times,
    round(
        case
            when li.duration_minutes is not null then li.duration_minutes::numeric / 3600
            when li.start_at is not null and li.end_at is not null then
                greatest(
                    extract(epoch from (li.end_at - li.start_at)) - coalesce(li.break_time_minutes, 0),
                    0
                )::numeric / 3600
            else null
        end,
        2
    ) as paid_hours,
    case
        when li.duration_minutes is not null then 'empower_duration_seconds'
        when li.start_at is not null and li.end_at is not null then 'calculated_start_end_less_break_seconds'
        else 'missing_times'
    end as paid_hours_source,
    li.cost,
    li.rate_of_pay,
    li.travel_time_minutes,
    round((coalesce(li.travel_time_minutes, 0)::numeric / 3600), 2) as travel_time_hours,
    li.waiting_time_minutes,
    round((coalesce(li.waiting_time_minutes, 0)::numeric / 3600), 2) as waiting_time_hours,
    li.client_mileage_distance,
    li.travel_mileage_distance,
    li.payload,
    li.synced_at,
    li.is_active
from public.timesheet_line_items li
join public.timesheets ts
    on ts.timesheet_identifier = li.timesheet_identifier
left join public.carers c
    on c.id = ts.carer_identifier
where li.is_active = true
  and ts.is_active = true;

create or replace view public.v_timesheet_detail_report
with (security_invoker = true)
as
select
    h.formatted_timesheet_number,
    h.timesheet_identifier,
    h.line_item_index + 1 as line_number,
    h.carer_identifier as carer_id,
    h.carer_name,
    h.primary_region_name,
    h.carer_payroll_number,
    h.timesheet_period_start,
    h.timesheet_period_end,
    h.paid_status,
    h.line_type,
    h.appointment_identifier,
    h.client_identifier,
    h.rate_description,
    h.rate_name,
    h.booking_reference,
    h.cancelled,
    h.local_start_at,
    h.local_end_at,
    h.week_start_date,
    h.week_end_date,
    h.starts_on_sunday,
    h.crosses_midnight,
    h.gross_hours_from_times,
    h.break_hours,
    h.paid_hours,
    h.paid_hours_source,
    h.rate_of_pay,
    h.cost,
    h.travel_time_hours,
    h.waiting_time_hours,
    h.client_mileage_distance,
    h.travel_mileage_distance,
    h.synced_at,
    cl.full_name as client_name,
    cl.primary_region_name as client_primary_region_name,
    ts.payment_group
from public.v_timesheet_line_item_hours h
join public.timesheets ts
    on ts.timesheet_identifier = h.timesheet_identifier
left join public.clients cl
    on cl.id = h.client_identifier;

create or replace view public.v_timesheet_extra_items_report
with (security_invoker = true)
as
select
    ei.extra_item_key,
    ei.timesheet_identifier,
    ei.extra_item_index + 1 as extra_item_number,
    ts.formatted_timesheet_number,
    ts.carer_identifier as carer_id,
    c.full_name as carer_name,
    c.primary_region_name,
    ts.carer_payroll_number,
    ts.period_start as timesheet_period_start,
    ts.period_end as timesheet_period_end,
    ts.paid_status,
    ei.description,
    ei.cost,
    ei.synced_at,
    ei.payload,
    ts.payment_group
from public.timesheet_extra_items ei
join public.timesheets ts
    on ts.timesheet_identifier = ei.timesheet_identifier
left join public.carers c
    on c.id = ts.carer_identifier
where ei.is_active = true
  and ts.is_active = true;

create or replace view public.v_weekly_carer_hours
with (security_invoker = true)
as
select
    h.week_start_date,
    h.week_end_date,
    h.carer_identifier as carer_id,
    h.carer_name,
    h.primary_region_name,
    h.carer_payroll_number,
    count(*) filter (where h.cancelled = false) as line_item_count,
    count(*) filter (where h.cancelled = true) as cancelled_line_item_count,
    count(distinct h.appointment_identifier) filter (
        where h.cancelled = false
          and h.appointment_identifier is not null
    ) as appointment_count,
    count(*) filter (
        where h.cancelled = false
          and h.crosses_midnight = true
    ) as overnight_shift_count,
    count(*) filter (
        where h.cancelled = false
          and h.starts_on_sunday = true
          and h.crosses_midnight = true
    ) as sunday_into_monday_shift_count,
    round(sum(h.paid_hours) filter (where h.cancelled = false), 2) as paid_hours,
    round(sum(h.gross_hours_from_times) filter (where h.cancelled = false), 2) as gross_hours,
    round(sum(h.break_hours) filter (where h.cancelled = false), 2) as break_hours,
    round(sum(h.travel_time_hours) filter (where h.cancelled = false), 2) as travel_time_hours,
    round(sum(h.waiting_time_hours) filter (where h.cancelled = false), 2) as waiting_time_hours,
    round(sum(h.cost) filter (where h.cancelled = false), 2) as total_cost
from public.v_timesheet_line_item_hours h
where h.week_start_date is not null
group by
    h.week_start_date,
    h.week_end_date,
    h.carer_identifier,
    h.carer_name,
    h.primary_region_name,
    h.carer_payroll_number;

create or replace view public.v_weekly_region_hours
with (security_invoker = true)
as
select
    week_start_date,
    week_end_date,
    coalesce(primary_region_name, 'Unknown') as primary_region_name,
    count(distinct carer_id) as carer_count,
    sum(line_item_count) as line_item_count,
    sum(appointment_count) as appointment_count,
    sum(overnight_shift_count) as overnight_shift_count,
    sum(sunday_into_monday_shift_count) as sunday_into_monday_shift_count,
    round(sum(paid_hours), 2) as paid_hours,
    round(sum(gross_hours), 2) as gross_hours,
    round(sum(break_hours), 2) as break_hours,
    round(sum(travel_time_hours), 2) as travel_time_hours,
    round(sum(waiting_time_hours), 2) as waiting_time_hours,
    round(sum(total_cost), 2) as total_cost
from public.v_weekly_carer_hours
group by
    week_start_date,
    week_end_date,
    coalesce(primary_region_name, 'Unknown');

create or replace view public.v_timesheet_hours_exceptions
with (security_invoker = true)
as
select
    h.*,
    case
        when h.start_at is null or h.end_at is null then 'Missing start/end'
        when h.end_at <= h.start_at then 'End before start'
        when h.duration_minutes is null then 'Missing Empower duration'
        when h.duration_minutes < 0 then 'Negative duration'
        when h.break_time_minutes < 0 then 'Negative break'
        when h.gross_hours_from_times >= 18 then 'Very long shift'
        else null
    end as exception_reason
from public.v_timesheet_line_item_hours h
where h.start_at is null
   or h.end_at is null
   or h.end_at <= h.start_at
   or h.duration_minutes is null
   or h.duration_minutes < 0
   or h.break_time_minutes < 0
   or h.gross_hours_from_times >= 18;

-- RLS: block anon/authenticated API access, but allow the existing Power BI
-- database role to read these objects if it has been created.
alter table public.timesheet_sync_runs enable row level security;
alter table public.timesheets_raw enable row level security;
alter table public.timesheets enable row level security;
alter table public.timesheet_line_items enable row level security;
alter table public.timesheet_extra_items enable row level security;

revoke all on table
    public.timesheet_sync_runs,
    public.timesheets_raw,
    public.timesheets,
    public.timesheet_line_items,
    public.timesheet_extra_items
from anon, authenticated;

do $$
begin
    if exists (select 1 from pg_roles where rolname = 'powerbi_reader') then
        grant select on table
            public.timesheets,
            public.timesheet_line_items,
            public.timesheet_extra_items,
            public.v_timesheet_line_item_hours,
            public.v_timesheet_detail_report,
            public.v_timesheet_extra_items_report,
            public.v_weekly_carer_hours,
            public.v_weekly_region_hours,
            public.v_timesheet_hours_exceptions
        to powerbi_reader;

        execute 'drop policy if exists "Power BI read timesheets" on public.timesheets';
        execute 'create policy "Power BI read timesheets" on public.timesheets for select to powerbi_reader using (true)';

        execute 'drop policy if exists "Power BI read timesheet line items" on public.timesheet_line_items';
        execute 'create policy "Power BI read timesheet line items" on public.timesheet_line_items for select to powerbi_reader using (true)';

        execute 'drop policy if exists "Power BI read timesheet extra items" on public.timesheet_extra_items';
        execute 'create policy "Power BI read timesheet extra items" on public.timesheet_extra_items for select to powerbi_reader using (true)';
    end if;
end;
$$;

commit;

-- Verification after running the schema and syncing data:
--
-- select count(*) from public.timesheets;
-- select count(*) from public.timesheet_line_items;
-- select * from public.v_timesheet_detail_report order by local_start_at desc limit 20;
-- select * from public.v_timesheet_line_item_hours order by start_at desc limit 20;
-- select * from public.v_weekly_carer_hours order by week_start_date desc, paid_hours desc limit 50;
-- select * from public.v_timesheet_hours_exceptions order by start_at desc limit 50;
