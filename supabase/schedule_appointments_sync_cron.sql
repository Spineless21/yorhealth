-- Schedule the Empower/Nourish appointments sync Edge Function.
--
-- Purpose:
-- Keep appointments/shift data fresh enough for the Power BI compliance rule:
-- Required + no document + no booked shifts = Pending.
--
-- Schedule:
-- 04:00 UTC daily.
-- This is 05:00 UK time during British Summer Time.
--
-- Notes:
-- - Supabase Cron uses pg_cron.
-- - HTTP calls use pg_net.
-- - pg_net requests are async; inspect net._http_response for failures.
-- - This assumes Verify JWT is OFF for sync-nourish-appointments.
-- - If you later set SYNC_SECRET on the function, add x-sync-secret to the headers.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Remove the old schedule first if it exists, so re-running this file is safe.
do $$
declare
    existing_jobid bigint;
begin
    select jobid
    into existing_jobid
    from cron.job
    where jobname = 'daily-sync-nourish-appointments'
    limit 1;

    if existing_jobid is not null then
        perform cron.unschedule(existing_jobid);
    end if;
end;
$$;

select cron.schedule(
    'daily-sync-nourish-appointments',
    '0 4 * * *',
    $$
    select net.http_get(
        url := 'https://riofkozqgsjnzlaocmam.supabase.co/functions/v1/sync-nourish-appointments',
        params := jsonb_build_object('days', '7'),
        headers := jsonb_build_object(
            'Content-Type', 'application/json'
        ),
        timeout_milliseconds := 300000
    ) as request_id;
    $$
);

-- Confirm the job exists.
select
    jobid,
    jobname,
    schedule,
    active,
    command
from cron.job
where jobname = 'daily-sync-nourish-appointments';

-- Check recent HTTP responses after the job runs.
-- pg_net response rows are retained only temporarily.
--
-- select
--     id,
--     status_code,
--     error_msg,
--     created,
--     content
-- from net._http_response
-- order by created desc
-- limit 20;
