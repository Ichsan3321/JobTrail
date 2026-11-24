begin;

create table public.applications (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    company text not null,
    position text not null,
    source text not null,
    applied_on date not null,
    status text not null,
    location text not null,
    work_type text not null,
    salary_monthly_idr bigint,
    notes text not null default '',
    revision integer not null default 1,
    create_fingerprint bytea not null,
    constraint applications_owner_key unique (user_id, id),
    constraint applications_required_text check (
        company ~ '[^[:space:]]' and position ~ '[^[:space:]]'
        and source ~ '[^[:space:]]' and location ~ '[^[:space:]]'
    ),
    constraint applications_status_code check (status in (
        'applied', 'screening', 'test', 'interview', 'offering', 'rejected'
    )),
    constraint applications_work_type_code check (work_type in ('on_site', 'hybrid', 'remote')),
    constraint applications_salary_nonnegative check (salary_monthly_idr >= 0),
    constraint applications_revision_positive check (revision > 0),
    constraint applications_applied_on_finite check (isfinite(applied_on))
);

create table public.agendas (
    id uuid primary key,
    user_id uuid not null,
    application_id uuid not null,
    type text not null,
    scheduled_at timestamptz not null,
    location_or_link text not null,
    notes text not null default '',
    create_fingerprint bytea not null,
    constraint agendas_owned_application_fk foreign key (user_id, application_id)
        references public.applications(user_id, id) on delete cascade,
    constraint agendas_type_code check (type in ('interview', 'test')),
    constraint agendas_location_required check (location_or_link ~ '[^[:space:]]'),
    constraint agendas_scheduled_at_finite check (isfinite(scheduled_at))
);

create table public.application_status_history (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,
    application_id uuid not null,
    status text not null,
    changed_at timestamptz not null,
    event_no integer not null,
    constraint history_owned_application_fk foreign key (user_id, application_id)
        references public.applications(user_id, id) on delete cascade,
    constraint history_application_order_key unique (application_id, event_no),
    constraint history_status_code check (status in (
        'applied', 'screening', 'test', 'interview', 'offering', 'rejected'
    )),
    constraint history_event_no_positive check (event_no > 0),
    constraint history_changed_at_finite check (isfinite(changed_at))
);

create table public.documents (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    title text not null,
    category text not null,
    file_name text not null,
    version text not null,
    updated_at timestamptz not null default statement_timestamp(),
    notes text not null default '',
    create_fingerprint bytea not null,
    constraint documents_owner_key unique (user_id, id),
    constraint documents_required_text check (
        title ~ '[^[:space:]]' and file_name ~ '[^[:space:]]' and version ~ '[^[:space:]]'
    ),
    constraint documents_category_code check (category in ('cv_resume', 'portfolio')),
    constraint documents_updated_at_finite check (isfinite(updated_at))
);

create table public.application_documents (
    user_id uuid not null,
    application_id uuid not null,
    document_id uuid not null,
    primary key (application_id, document_id),
    constraint links_owned_application_fk foreign key (user_id, application_id)
        references public.applications(user_id, id) on delete cascade,
    constraint links_owned_document_fk foreign key (user_id, document_id)
        references public.documents(user_id, id) on delete no action
);

create index applications_owner_date_idx on public.applications (user_id, applied_on, id);
create index agendas_owner_schedule_idx on public.agendas (user_id, scheduled_at);
create index agendas_application_schedule_idx on public.agendas (user_id, application_id, scheduled_at);
create index history_application_time_idx on public.application_status_history
    (user_id, application_id, changed_at, event_no);
create index documents_owner_updated_idx on public.documents (user_id, updated_at);
create index links_document_idx on public.application_documents (user_id, document_id);

alter table public.applications enable row level security;
alter table public.agendas enable row level security;
alter table public.application_status_history enable row level security;
alter table public.documents enable row level security;
alter table public.application_documents enable row level security;
revoke all on public.applications, public.agendas, public.application_status_history,
    public.documents, public.application_documents from public, anon, authenticated, service_role;

commit;
