-- Template: mark "never provided" compliance items as Pending when the carer has no booked shifts.
--
-- Use this pattern inside public.v_carer_checklist_status once the shift/appointment
-- source table is confirmed.
--
-- Business rule:
-- If a carer has never uploaded a document for a checklist type AND has no booked
-- shifts, mark the item as Pending instead of Non-Compliant/Outstanding in Power BI.
--
-- Keep the raw Empower/API status visible, but add reporting fields so Power BI
-- can show the row cleanly.

-- 1) Add this lateral join to the view, after the carers/checklist joins.
--
left join lateral (
    select true as has_booked_shifts
    from public.v_carer_shift_activity sa
    where sa.carer_id = c.id
      and sa.future_booked_shift_count > 0
    limit 1
) shift_activity on true

-- 2) Add these derived columns to the SELECT.
--
-- "r" is the selected checklist_records lateral join in the current view.
-- "s" is checklist_type_status.

coalesce(shift_activity.has_booked_shifts, false) as has_booked_shifts,

case
    when r.file_identifier is not null
      or r.document_upload_date is not null
      or r.completion_date is not null
      or r.expires_on is not null
      or r.document_review_date is not null
        then true
    else false
end as has_document_record,

case
    when s.status = 'Required'
     and not (
            r.file_identifier is not null
         or r.document_upload_date is not null
         or r.completion_date is not null
         or r.expires_on is not null
         or r.document_review_date is not null
     )
     and coalesce(shift_activity.has_booked_shifts, false) = false
        then true
    else false
end as is_pending_compliance_item,

case
    when s.status = 'Required'
     and not (
            r.file_identifier is not null
         or r.document_upload_date is not null
         or r.completion_date is not null
         or r.expires_on is not null
         or r.document_review_date is not null
     )
     and coalesce(shift_activity.has_booked_shifts, false) = false
        then 'Pending'
    -- keep the existing compliance_display_status logic after this branch
end as compliance_display_status

-- 3) Update the boolean flags so Power BI counts stay right.
--
-- Existing:
-- case when s.status = 'Required' then true else false end as is_missing
-- case when s.status <> 'Current' then true else false end as is_non_compliant
--
-- Replace with:

case
    when s.status = 'Required'
     and not (
            r.file_identifier is not null
         or r.document_upload_date is not null
         or r.completion_date is not null
         or r.expires_on is not null
         or r.document_review_date is not null
     )
     and coalesce(shift_activity.has_booked_shifts, false) = false
        then false
    when s.status = 'Required'
        then true
    else false
end as is_missing,

case
    when s.status = 'Required'
     and not (
            r.file_identifier is not null
         or r.document_upload_date is not null
         or r.completion_date is not null
         or r.expires_on is not null
         or r.document_review_date is not null
     )
     and coalesce(shift_activity.has_booked_shifts, false) = false
        then false
    when s.status <> 'Current'
        then true
    else false
end as is_non_compliant
