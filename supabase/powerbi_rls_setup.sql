-- Power BI read-only access + RLS setup for the Empower compliance model.
--
-- Run this in Supabase SQL Editor.
-- IMPORTANT:
-- 1. Replace CHANGE_ME_USE_A_LONG_RANDOM_PASSWORD before running.
-- 2. After running, update Power BI credentials to use:
--      Direct host username: powerbi_reader
--      Pooler username:      powerbi_reader.riofkozqgsjnzlaocmam
-- 3. Keep using SSL/encrypted connection.

begin;

-- 1) Dedicated read-only database role for Power BI.
do $$
begin
    if not exists (
        select 1
        from pg_roles
        where rolname = 'powerbi_reader'
    ) then
        create role powerbi_reader
            login
            password 'CHANGE_ME_USE_A_LONG_RANDOM_PASSWORD'
            nosuperuser
            nocreatedb
            nocreaterole
            noinherit
            noreplication;
    end if;
end;
$$;

grant connect on database postgres to powerbi_reader;
grant usage on schema public to powerbi_reader;

-- 2) Grant read access only to the reporting objects Power BI needs.
--    Add/remove objects here if your report starts using more tables.
grant select on table
    public.carers,
    public.checklist_records,
    public.checklist_type_status,
    public.checklist_types,
    public.v_carer_checklist_status,
    public.v_carer_compliance_summary
to powerbi_reader;

-- Optional, if you created the weekly snapshot table.
do $$
begin
    if to_regclass('public.carer_compliance_weekly_snapshot') is not null then
        grant select on table public.carer_compliance_weekly_snapshot to powerbi_reader;
    end if;
end;
$$;

-- Optional, if older Power BI pages still use this view.
do $$
begin
    if to_regclass('public.v_carer_checklist') is not null then
        grant select on table public.v_carer_checklist to powerbi_reader;
    end if;
end;
$$;

-- 3) Make views respect the querying user's permissions/RLS where supported.
--    Postgres 15+ supports security_invoker and your project is on Postgres 17.
do $$
begin
    if to_regclass('public.v_carer_checklist_status') is not null then
        execute 'alter view public.v_carer_checklist_status set (security_invoker = true)';
    end if;

    if to_regclass('public.v_carer_compliance_summary') is not null then
        execute 'alter view public.v_carer_compliance_summary set (security_invoker = true)';
    end if;

    if to_regclass('public.v_carer_checklist') is not null then
        execute 'alter view public.v_carer_checklist set (security_invoker = true)';
    end if;
end;
$$;

-- 4) Policies for the base reporting tables.
--    These allow Power BI read-only access while RLS blocks public API access.
drop policy if exists "Power BI read carers" on public.carers;
create policy "Power BI read carers"
on public.carers
for select
to powerbi_reader
using (true);

drop policy if exists "Power BI read checklist records" on public.checklist_records;
create policy "Power BI read checklist records"
on public.checklist_records
for select
to powerbi_reader
using (true);

drop policy if exists "Power BI read checklist type status" on public.checklist_type_status;
create policy "Power BI read checklist type status"
on public.checklist_type_status
for select
to powerbi_reader
using (true);

drop policy if exists "Power BI read checklist types" on public.checklist_types;
create policy "Power BI read checklist types"
on public.checklist_types
for select
to powerbi_reader
using (true);

do $$
begin
    if to_regclass('public.carer_compliance_weekly_snapshot') is not null then
        execute 'drop policy if exists "Power BI read weekly snapshot" on public.carer_compliance_weekly_snapshot';
        execute '
            create policy "Power BI read weekly snapshot"
            on public.carer_compliance_weekly_snapshot
            for select
            to powerbi_reader
            using (true)
        ';
    end if;
end;
$$;

-- 5) Enable RLS after policies are in place.
alter table public.carers enable row level security;
alter table public.checklist_records enable row level security;
alter table public.checklist_type_status enable row level security;
alter table public.checklist_types enable row level security;

do $$
begin
    if to_regclass('public.carer_compliance_weekly_snapshot') is not null then
        execute 'alter table public.carer_compliance_weekly_snapshot enable row level security';
    end if;
end;
$$;

-- 6) Remove broad API role access.
--    This is what stops anon/authenticated Data API access from reading the tables.
revoke all on table
    public.carers,
    public.checklist_records,
    public.checklist_type_status,
    public.checklist_types
from anon, authenticated;

do $$
begin
    if to_regclass('public.carer_compliance_weekly_snapshot') is not null then
        execute 'revoke all on table public.carer_compliance_weekly_snapshot from anon, authenticated';
    end if;
end;
$$;

-- 7) Verification: this should return rows after the migration.
--    Run the verification block separately if your SQL Editor does not display it.
-- set role powerbi_reader;
-- select count(*) as checklist_rows from public.v_carer_checklist_status;
-- select count(*) as summary_rows from public.v_carer_compliance_summary;
-- reset role;

commit;

