-- Add fields used when syncing recruitment calendar events from Microsoft Graph.
-- Safe to run more than once.

alter table public.ats_interview_events
    add column if not exists source text not null default 'ats',
    add column if not exists graph_ical_uid text,
    add column if not exists graph_change_key text,
    add column if not exists graph_series_master_id text,
    add column if not exists graph_created_at timestamptz,
    add column if not exists graph_last_modified_at timestamptz,
    add column if not exists graph_is_cancelled boolean not null default false,
    add column if not exists linked_at timestamptz,
    add column if not exists linked_by_bubble_user_id text,
    add column if not exists linked_by_name text;

create index if not exists idx_ats_interview_events_source
    on public.ats_interview_events(source);

create index if not exists idx_ats_interview_events_graph_ical_uid
    on public.ats_interview_events(graph_ical_uid);

create unique index if not exists ux_ats_interview_events_graph_event_id
    on public.ats_interview_events(graph_event_id)
    where graph_event_id is not null;
