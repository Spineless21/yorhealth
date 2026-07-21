-- Verification queries after syncing appointments.

-- 1) Basic row counts.
select
    (select count(*) from public.appointments_raw) as appointments_raw_rows,
    (select count(*) from public.appointments) as appointments_rows,
    (select count(*) from public.appointment_carers) as appointment_carer_rows;

-- 2) Check whether appointment carer identifiers match carers.id.
select
    count(*) filter (where ac.carer_identifier is not null) as appointment_carer_slots_with_carer,
    count(*) filter (where ac.carer_identifier is not null and c.id is not null) as matched_to_carers,
    count(*) filter (where ac.carer_identifier is not null and c.id is null) as unmatched_to_carers
from public.appointment_carers ac
left join public.carers c
    on c.id = ac.carer_identifier;

-- 3) List any appointment carers that do not match the carers table.
select
    ac.carer_identifier,
    count(*) as appointment_slots
from public.appointment_carers ac
left join public.carers c
    on c.id = ac.carer_identifier
where ac.carer_identifier is not null
  and c.id is null
group by ac.carer_identifier
order by appointment_slots desc;

-- 4) Future booked shifts by carer.
select
    c.full_name as carer_name,
    c.primary_region_name,
    sa.future_booked_shift_count,
    sa.next_shift_start_at,
    sa.historic_shift_count,
    sa.last_shift_start_at
from public.v_carer_shift_activity sa
left join public.carers c
    on c.id = sa.carer_id
order by
    sa.future_booked_shift_count desc,
    c.full_name;

-- 5) Appointment rows that should not count as booked shifts.
select
    appointment_identifier,
    carer_identifier,
    start_at,
    cancelled,
    deleted,
    is_active
from public.appointment_carers
where carer_identifier is null
   or cancelled = true
   or deleted = true
   or is_active = false
order by start_at;
