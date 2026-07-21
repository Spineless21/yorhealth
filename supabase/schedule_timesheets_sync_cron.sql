-- Schedule the Empower/Nourish timesheets sync Edge Function.
--
-- Purpose:
-- Keep weekly true-hours reporting fresh for Power BI.
--
-- Schedule:
-- 04:30 UTC daily.
-- This is 05:30 UK time during British Summer Time.
--
-- Notes:
-- - Supabase Cron uses pg_cron.
-- - HTTP calls use pg_net.
-- - pg_net requests are async; inspect net._http_response for failures.
-- - This assumes Verify JWT is OFF for sync-nourish-timesheets.
-- - If you set SYNC_SECRET on the function, add x-sync-secret to the headers.
-- - The default rolling window is 90 days back and 14 days forward.

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
    where jobname = 'daily-sync-nourish-timesheets'
    limit 1;

    if existing_jobid is not null then
        perform cron.unschedule(existing_jobid);
    end if;
end;
$$;

select cron.schedule(
    'daily-sync-nourish-timesheets',
    '30 4 * * *',
    $$
    select net.http_get(
        url := 'https://riofkozqgsjnzlaocmam.supabase.co/functions/v1/sync-nourish-timesheets',
        params := jsonb_build_object(
            'days_back', '90',
            'days_forward', '14',
            'max_pages', '50'
        ),
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
where jobname = 'daily-sync-nourish-timesheets';

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
