-- Debug why Tiffany Charlesworth DBS still appears as Expired.
--
-- Run these in Supabase SQL Editor and review the three result sets.

-- 1) What Power BI/view currently sees.
select
    carer_id,
    carer_name,
    primary_region_name,
    checklist_type_identifier,
    checklist_type_name,
    api_checklist_status,
    checklist_status,
    compliance_display_status,
    is_expired,
    is_non_compliant,
    has_newer_valid_document,
    has_document_record,
    effective_expiry_date,
    expires_on,
    document_review_date,
    document_upload_date,
    record_modified_at,
    synced_at as status_synced_at,
    last_seen_at as status_last_seen_at,
    document_description,
    file_identifier
from public.v_carer_checklist_status
where lower(carer_name) = lower('Tiffany Charlesworth')
  and checklist_reporting_group = 'DBS';

-- 2) What the raw checklist status API last said for DBS.
select
    c.id as carer_id,
    c.full_name,
    s.checklist_type_identifier,
    s.status,
    s.synced_at,
    s.last_seen_at,
    s.is_active,
    s.*
from public.carers c
join public.checklist_type_status s
    on s.user_identifier = c.id
where lower(c.full_name) = lower('Tiffany Charlesworth')
  and s.checklist_type_identifier = '1'
order by s.synced_at desc nulls last;

-- 3) All DBS-like checklist records for Tiffany.
--    This shows whether the new DBS exists, whether it has a future expiry,
--    and whether the current lateral join would pick it.
select
    r.id,
    r.user_identifier,
    r.type,
    r.checklist_type_name,
    r.document_description,
    r.completion_date,
    r.expires_on,
    r.document_review_date,
    coalesce(r.expires_on, r.document_review_date) as effective_expiry_date,
    r.document_upload_date,
    r.modified_at,
    r.synced_at,
    r.last_seen_at,
    r.is_active,
    r.deleted,
    r.file_identifier,
    r.is_expired,
    r.days_until_expiry,
    r.review_status,
    case
        when r.type = 1 then true
        when r.type is null and lower(trim(r.document_description)) = 'dbs' then true
        else false
    end as would_match_current_view_join,
    case
        when coalesce(r.expires_on, r.document_review_date)::date >= current_date then true
        else false
    end as has_valid_effective_expiry
from public.carers c
join public.checklist_records r
    on r.user_identifier = c.id
where lower(c.full_name) = lower('Tiffany Charlesworth')
  and (
      r.type = 1
      or lower(coalesce(r.document_description, '')) like '%dbs%'
      or lower(coalesce(r.checklist_type_name, '')) like '%dbs%'
  )
order by
    coalesce(r.expires_on, r.document_review_date) desc nulls last,
    r.document_upload_date desc nulls last,
    r.modified_at desc nulls last;

-- 4) Quick diagnosis flag.
--    If this returns true for has_valid_dbs_record but the view still says Expired,
--    the view override condition is too strict.
with view_row as (
    select *
    from public.v_carer_checklist_status
    where lower(carer_name) = lower('Tiffany Charlesworth')
      and checklist_reporting_group = 'DBS'
),
valid_record as (
    select
        count(*) > 0 as has_valid_dbs_record,
        max(coalesce(r.expires_on, r.document_review_date)) as latest_valid_expiry,
        max(greatest(
            coalesce(r.modified_at, '-infinity'::timestamptz),
            coalesce(r.document_upload_date, '-infinity'::timestamptz)
        )) as latest_valid_record_update
    from public.carers c
    join public.checklist_records r
        on r.user_identifier = c.id
    where lower(c.full_name) = lower('Tiffany Charlesworth')
      and r.is_active = true
      and coalesce(r.deleted, false) = false
      and (
          r.type = 1
          or r.type is null and lower(trim(r.document_description)) = 'dbs'
      )
      and coalesce(r.expires_on, r.document_review_date)::date >= current_date
)
select
    v.carer_name,
    v.api_checklist_status,
    v.checklist_status,
    v.compliance_display_status,
    v.effective_expiry_date as view_effective_expiry_date,
    v.has_newer_valid_document,
    v.last_seen_at as status_last_seen_at,
    vr.has_valid_dbs_record,
    vr.latest_valid_expiry,
    vr.latest_valid_record_update,
    case
        when vr.has_valid_dbs_record = true
          and v.checklist_status = 'Expired'
            then 'Likely view override condition is too strict or current view selected the wrong record'
        when vr.has_valid_dbs_record = false
            then 'No active valid DBS record found in checklist_records; rerun checklist records sync'
        else 'View appears aligned with records'
    end as likely_reason
from view_row v
cross join valid_record vr;
