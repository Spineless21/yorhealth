-- Update public.v_carer_checklist_status to include the appointment-based Pending rule.
--
-- Business rule:
-- Required/Expired + no booked future shifts = Pending.
-- A valid DBS/Right to Work document override still wins before Pending.
--
-- Pending does not count as missing/non-compliant/outstanding.

create or replace view public.v_carer_checklist_status as
with
  base as (
    select
      c.id as carer_id,
      c.full_name as carer_name,
      c.primary_region_name,
      c.job_title,
      c.status_title as carer_status,
      c.address_full,
      c.address_line_1,
      c.town,
      c.locality,
      c.postcode,
      c.country,
      c.latitude,
      c.longitude,
      s.checklist_type_identifier,
      COALESCE(
        ct.checklist_type_name,
        concat('Unknown Type ', s.checklist_type_identifier)
      ) as checklist_type_name,
      ct.checklist_category,
      ct.reporting_group,
      s.status as api_checklist_status,
      s.synced_at,
      s.last_seen_at,
      s.is_active,
      r.completion_date,
      r.expires_on,
      r.document_review_date,
      r.document_upload_date,
      r.document_description,
      r.file_identifier,
      r.modified_at as record_modified_at,
      coalesce(sa.future_booked_shift_count, 0) as future_booked_shift_count,
      sa.next_shift_start_at,
      coalesce(sa.historic_shift_count, 0) as historic_shift_count,
      sa.last_shift_start_at,
      case
        when coalesce(sa.future_booked_shift_count, 0) > 0 then true
        else false
      end as has_booked_shifts,
      case
        when r.id is not null then true
        else false
      end as has_document_record,
      case
        when (
          s.checklist_type_identifier = any (array['1'::text, '2'::text])
        )
        and (
          s.status = any (array['Required'::text, 'Expired'::text])
        )
        and COALESCE(r.expires_on, r.document_review_date)::date >= CURRENT_DATE then true
        else false
      end as has_newer_valid_document
    from
      carers c
      left join checklist_type_status s on c.id = s.user_identifier
      and s.is_active = true
      left join checklist_types ct on s.checklist_type_identifier::integer = ct.checklist_type_identifier
      left join v_carer_shift_activity sa on sa.carer_id = c.id
      left join lateral (
        select
          r_1.id,
          r_1.user_identifier,
          r_1.type,
          r_1.completion_date,
          r_1.expires_on,
          r_1.file_identifier,
          r_1.modified_at,
          r_1.modified_by,
          r_1.document_description,
          r_1.document_review_date,
          r_1.document_reviewed_by,
          r_1.document_upload_date,
          r_1.deleted,
          r_1.synced_at,
          r_1.is_active,
          r_1.last_seen_at,
          r_1.checklist_type_name,
          r_1.is_expired,
          r_1.days_until_expiry,
          r_1.is_review_due,
          r_1.is_missing_review,
          r_1.review_status
        from
          checklist_records r_1
        where
          r_1.user_identifier = c.id
          and r_1.is_active = true
          and COALESCE(r_1.deleted, false) = false
          and (
            r_1.type = s.checklist_type_identifier::integer
            or r_1.type is null
            and lower(
              TRIM(
                both
                from
                  r_1.document_description
              )
            ) = lower(
              TRIM(
                both
                from
                  ct.checklist_type_name
              )
            )
          )
        order by
          (
            COALESCE(r_1.expires_on, r_1.document_review_date)
          ) desc nulls last,
          r_1.completion_date desc nulls last,
          r_1.document_upload_date desc nulls last,
          r_1.modified_at desc nulls last
        limit
          1
      ) r on true
    where
      c.is_active = true
  ),
  resolved as (
    select
      base.carer_id,
      base.carer_name,
      base.primary_region_name,
      base.job_title,
      base.carer_status,
      base.address_full,
      base.address_line_1,
      base.town,
      base.locality,
      base.postcode,
      base.country,
      base.latitude,
      base.longitude,
      base.checklist_type_identifier,
      base.checklist_type_name,
      base.checklist_category,
      base.reporting_group,
      base.api_checklist_status,
      base.synced_at,
      base.last_seen_at,
      base.is_active,
      base.completion_date,
      base.expires_on,
      base.document_review_date,
      base.document_upload_date,
      base.document_description,
      base.file_identifier,
      base.record_modified_at,
      base.future_booked_shift_count,
      base.next_shift_start_at,
      base.historic_shift_count,
      base.last_shift_start_at,
      base.has_booked_shifts,
      base.has_document_record,
      base.has_newer_valid_document,
      case
        when base.has_newer_valid_document then false
        when base.api_checklist_status = any (array['Required'::text, 'Expired'::text])
          and base.has_booked_shifts = false
            then true
        else false
      end as is_pending_compliance_item,
      case
        when base.has_newer_valid_document then 'Current'::text
        when base.api_checklist_status = any (array['Required'::text, 'Expired'::text])
          and base.has_booked_shifts = false
            then 'Pending'::text
        else base.api_checklist_status
      end as resolved_checklist_status
    from
      base
  )
select
  carer_id,
  carer_name,
  primary_region_name,
  job_title,
  carer_status,
  address_full,
  address_line_1,
  town,
  locality,
  postcode,
  country,
  latitude,
  longitude,
  checklist_type_identifier,
  checklist_type_name,
  checklist_category,
  resolved_checklist_status as checklist_status,
  case
    when resolved_checklist_status = any (array['Current'::text, 'Expiring Soon'::text]) then true
    else false
  end as is_compliant,
  case
    when resolved_checklist_status = 'Required'::text then true
    else false
  end as is_required,
  case
    when resolved_checklist_status = 'Required'::text then true
    else false
  end as is_missing,
  case
    when resolved_checklist_status = 'Expired'::text then true
    else false
  end as is_expired,
  case
    when resolved_checklist_status = any (array['Required'::text, 'Expired'::text]) then true
    else false
  end as is_non_compliant,
  completion_date,
  expires_on,
  document_review_date,
  document_upload_date,
  document_description,
  file_identifier,
  case
    when resolved_checklist_status = any (array['Required'::text, 'Pending'::text]) then null::timestamp with time zone
    else COALESCE(expires_on, document_review_date)
  end as effective_expiry_date,
  case
    when resolved_checklist_status = 'Pending'::text then 'Pending'::text
    when resolved_checklist_status = 'Required'::text then 'Not Provided'::text
    when resolved_checklist_status = 'Expired'::text then 'Expired'::text
    when resolved_checklist_status = 'Expiring Soon'::text then 'Expiring Soon'::text
    when resolved_checklist_status = 'Current'::text
      and COALESCE(expires_on, document_review_date)::date <= (CURRENT_DATE + '30 days'::interval) then 'Expiring Soon'::text
    when resolved_checklist_status = 'Current'::text then 'Valid'::text
    else 'Unknown'::text
  end as compliance_display_status,
  synced_at,
  last_seen_at,
  is_active,
  case
    when resolved_checklist_status = 'Expiring Soon'::text then true
    when resolved_checklist_status = 'Current'::text
      and COALESCE(expires_on, document_review_date)::date <= (CURRENT_DATE + '30 days'::interval) then true
    else false
  end as is_warning,
  reporting_group as checklist_reporting_group,
  api_checklist_status,
  has_newer_valid_document,
  record_modified_at,
  future_booked_shift_count,
  next_shift_start_at,
  historic_shift_count,
  last_shift_start_at,
  has_booked_shifts,
  has_document_record,
  is_pending_compliance_item as is_pending
from
  resolved;

-- Quick checks after running:
--
-- select
--   checklist_reporting_group,
--   checklist_status,
--   compliance_display_status,
--   count(*) as document_rows,
--   count(distinct carer_id) as carers
-- from public.v_carer_checklist_status
-- where checklist_reporting_group in ('DBS', 'Right to Work', 'Sponsorship')
-- group by checklist_reporting_group, checklist_status, compliance_display_status
-- order by checklist_reporting_group, checklist_status, compliance_display_status;
--
-- select
--   carer_name,
--   checklist_reporting_group,
--   checklist_status,
--   compliance_display_status,
--   has_document_record,
--   has_booked_shifts,
--   future_booked_shift_count,
--   next_shift_start_at
-- from public.v_carer_checklist_status
-- where checklist_status = 'Pending'
-- order by carer_name, checklist_reporting_group;
