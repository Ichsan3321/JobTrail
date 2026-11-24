begin;

create role jobtrail_mutator nologin noinherit nobypassrls;
grant jobtrail_mutator to current_user;
create schema jobtrail_private;
revoke all on schema jobtrail_private from public, anon, authenticated, service_role;
grant usage on schema jobtrail_private, public to jobtrail_mutator;

-- Supabase's migration role can call auth.uid() but cannot delegate auth schema access.
-- This bridge returns the request identity only and has no table access in its body.
create function jobtrail_private.request_user_id() returns uuid
language sql stable security definer set search_path = ''
as $$
    select auth.uid();
$$;

do $$
declare
    table_name text;
begin
    foreach table_name in array array[
        'applications', 'agendas', 'application_status_history', 'documents', 'application_documents'
    ] loop
        execute format('alter table public.%I force row level security', table_name);
        execute format(
            'create policy owner_read on public.%I for select to authenticated
             using (user_id = (select auth.uid()))', table_name
        );
        execute format(
            'create policy mutation_owner_read on public.%I for select to jobtrail_mutator
             using (user_id = (select jobtrail_private.request_user_id()))', table_name
        );
        execute format(
            'create policy owner_insert on public.%I for insert to jobtrail_mutator
             with check (user_id = (select jobtrail_private.request_user_id()))', table_name
        );
        if table_name in ('applications', 'agendas', 'documents') then
            execute format(
                'create policy owner_update on public.%I for update to jobtrail_mutator
                 using (user_id = (select jobtrail_private.request_user_id()))
                 with check (user_id = (select jobtrail_private.request_user_id()))',
                table_name
            );
        end if;
        if table_name <> 'application_status_history' then
            execute format(
                'create policy owner_delete on public.%I for delete to jobtrail_mutator
                 using (user_id = (select jobtrail_private.request_user_id()))', table_name
            );
        end if;
    end loop;
end
$$;

grant select (id, user_id, company, position, source, applied_on, status, location,
    work_type, salary_monthly_idr, notes, revision) on public.applications to authenticated;
grant select (id, user_id, application_id, type, scheduled_at, location_or_link, notes)
    on public.agendas to authenticated;
grant select (id, user_id, title, category, file_name, version, updated_at, notes)
    on public.documents to authenticated;
grant select on public.application_status_history, public.application_documents to authenticated;

grant select, insert, delete on public.applications, public.agendas, public.documents,
    public.application_documents to jobtrail_mutator;
grant select, insert on public.application_status_history to jobtrail_mutator;
grant update (company, position, source, applied_on, status, location, work_type,
    salary_monthly_idr, notes, revision) on public.applications to jobtrail_mutator;
grant update (application_id, type, scheduled_at, location_or_link, notes)
    on public.agendas to jobtrail_mutator;
grant update (title, category, file_name, version, updated_at, notes)
    on public.documents to jobtrail_mutator;

create function jobtrail_private.require_user() returns uuid
language plpgsql stable set search_path = ''
as $$
declare
    actor uuid := jobtrail_private.request_user_id();
begin
    if actor is null then
        raise exception using errcode = '42501', message = 'Authentication required';
    end if;
    return actor;
end
$$;

create function jobtrail_private.trim_text(p_value text) returns text
language sql immutable strict set search_path = ''
as $$
    select pg_catalog.regexp_replace(p_value, '^[[:space:]]+|[[:space:]]+$', '', 'g');
$$;

create function jobtrail_private.wib_date(p_instant timestamptz) returns date
language sql immutable strict set search_path = ''
as $$
    select (p_instant at time zone interval '+07:00')::date;
$$;

create function jobtrail_private.fingerprint(p_value jsonb) returns bytea
language sql immutable strict set search_path = ''
as $$
    select pg_catalog.sha256(pg_catalog.convert_to(p_value::text, 'UTF8'));
$$;

create function jobtrail_private.canonical_links(p_ids uuid[]) returns uuid[]
language plpgsql immutable set search_path = ''
as $$
declare
    result uuid[];
begin
    if p_ids is null then
        raise exception using errcode = '22023', message = 'Document IDs are required';
    end if;
    select coalesce(array_agg(distinct id order by id), '{}'::uuid[])
    into result from unnest(p_ids) as ids(id) where id is not null;
    if cardinality(result) <> cardinality(p_ids) then
        raise exception using errcode = '22023', message = 'Document IDs must be distinct and nonnull';
    end if;
    return result;
end
$$;

create function jobtrail_private.replace_links(p_actor uuid, p_id uuid, p_ids uuid[]) returns void
language plpgsql set search_path = ''
as $$
begin
    delete from public.application_documents
    where user_id = p_actor and application_id = p_id and document_id <> all(p_ids);
    insert into public.application_documents (user_id, application_id, document_id)
    select p_actor, p_id, doc_id from unnest(p_ids) as ids(doc_id)
    on conflict (application_id, document_id) do nothing;
exception when foreign_key_violation then
    raise exception using errcode = 'JT003', message = 'Document link unavailable';
end
$$;

create function jobtrail_private.lock_application(p_actor uuid, p_id uuid)
returns public.applications
language plpgsql set search_path = ''
as $$
declare
    app public.applications;
begin
    select * into app from public.applications
    where user_id = p_actor and id = p_id for update;
    if not found then
        raise exception using errcode = 'JT001', message = 'Record unavailable';
    end if;
    return app;
end
$$;

create function jobtrail_private.check_application_date(p_date date) returns void
language plpgsql stable set search_path = ''
as $$
begin
    if p_date is null or not isfinite(p_date)
        or p_date > jobtrail_private.wib_date(statement_timestamp()) then
        raise exception using errcode = '22023', message = 'Invalid application date';
    end if;
end
$$;

create function jobtrail_private.append_history(p_actor uuid, p_id uuid, p_status text)
returns void
language sql set search_path = ''
as $$
    insert into public.application_status_history
        (user_id, application_id, status, changed_at, event_no)
    select p_actor, p_id, p_status, greatest(statement_timestamp(), max(changed_at)),
        coalesce(max(event_no), 0) + 1
    from public.application_status_history where user_id = p_actor and application_id = p_id;
$$;

revoke all on all functions in schema jobtrail_private from public, anon, authenticated, service_role;
grant execute on all functions in schema jobtrail_private to jobtrail_mutator;

-- RPCs return identifiers and revisions. Snapshot reads provide canonical DTOs.
create function public.jobtrail_create_application(
    p_id uuid, p_company text, p_position text, p_source text, p_applied_on date,
    p_status text, p_location text, p_work_type text, p_salary_monthly_idr bigint default null,
    p_notes text default '', p_document_ids uuid[] default '{}'
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    actor uuid := jobtrail_private.require_user();
    links uuid[] := jobtrail_private.canonical_links(p_document_ids);
    app public.applications;
    payload_hash bytea;
    replayed boolean := false;
begin
    p_company := jobtrail_private.trim_text(p_company);
    p_position := jobtrail_private.trim_text(p_position);
    p_source := jobtrail_private.trim_text(p_source);
    p_location := jobtrail_private.trim_text(p_location);
    perform jobtrail_private.check_application_date(p_applied_on);
    payload_hash := jobtrail_private.fingerprint(jsonb_build_array(
        p_company, p_position, p_source, p_applied_on - date '2000-01-01', p_status,
        p_location, p_work_type, p_salary_monthly_idr, p_notes, links
    ));
    insert into public.applications (id, user_id, company, position, source, applied_on,
        status, location, work_type, salary_monthly_idr, notes, create_fingerprint)
    values (p_id, actor, p_company, p_position, p_source, p_applied_on, p_status,
        p_location, p_work_type, p_salary_monthly_idr, p_notes, payload_hash)
    on conflict (id) do nothing returning * into app;
    if found then
        perform jobtrail_private.replace_links(actor, p_id, links);
        perform jobtrail_private.append_history(actor, p_id, p_status);
    else
        select * into app from public.applications
        where user_id = actor and id = p_id for update;
        if not found or app.create_fingerprint <> payload_hash then
            raise exception using errcode = 'JT004', message = 'Create ID conflict';
        end if;
        replayed := true;
    end if;
    return jsonb_build_object('id', app.id, 'revision', app.revision, 'replayed', replayed);
end
$$;

create function public.jobtrail_update_application(
    p_id uuid, p_expected_revision integer, p_company text, p_position text, p_source text,
    p_applied_on date, p_status text, p_location text, p_work_type text,
    p_salary_monthly_idr bigint, p_notes text, p_document_ids uuid[]
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    actor uuid := jobtrail_private.require_user();
    app public.applications := jobtrail_private.lock_application(actor, p_id);
    links uuid[] := jobtrail_private.canonical_links(p_document_ids);
    next_revision integer;
begin
    if p_expected_revision is distinct from app.revision then
        raise exception using errcode = 'JT002', message = 'Stale application revision';
    end if;
    perform jobtrail_private.check_application_date(p_applied_on);
    if exists (select 1 from public.agendas
               where user_id = actor and application_id = p_id
                 and jobtrail_private.wib_date(scheduled_at) < p_applied_on)
       or exists (select 1 from public.application_status_history
                  where user_id = actor and application_id = p_id
                    and jobtrail_private.wib_date(changed_at) < p_applied_on) then
        raise exception using errcode = '22023', message = 'Application date invalidates related records';
    end if;
    update public.applications
    set company = jobtrail_private.trim_text(p_company),
        position = jobtrail_private.trim_text(p_position),
        source = jobtrail_private.trim_text(p_source), applied_on = p_applied_on,
        status = p_status, location = jobtrail_private.trim_text(p_location),
        work_type = p_work_type, salary_monthly_idr = p_salary_monthly_idr,
        notes = p_notes, revision = revision + 1
    where user_id = actor and id = p_id returning revision into next_revision;
    perform jobtrail_private.replace_links(actor, p_id, links);
    if app.status <> p_status then
        perform jobtrail_private.append_history(actor, p_id, p_status);
    end if;
    return jsonb_build_object('id', p_id, 'revision', next_revision);
end
$$;

create function public.jobtrail_change_status(
    p_id uuid, p_expected_revision integer, p_status text
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    actor uuid := jobtrail_private.require_user();
    app public.applications := jobtrail_private.lock_application(actor, p_id);
begin
    if p_expected_revision is distinct from app.revision then
        raise exception using errcode = 'JT002', message = 'Stale application revision';
    end if;
    if app.status is distinct from p_status then
        perform jobtrail_private.check_application_date(app.applied_on);
        update public.applications set status = p_status, revision = revision + 1
        where user_id = actor and id = p_id returning revision into app.revision;
        perform jobtrail_private.append_history(actor, p_id, p_status);
    end if;
    return jsonb_build_object('id', p_id, 'revision', app.revision);
end
$$;

create function public.jobtrail_delete_application(p_id uuid, p_expected_revision integer)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
    actor uuid := jobtrail_private.require_user();
    app public.applications := jobtrail_private.lock_application(actor, p_id);
begin
    if p_expected_revision is distinct from app.revision then
        raise exception using errcode = 'JT002', message = 'Stale application revision';
    end if;
    delete from public.applications where user_id = actor and id = p_id;
    return p_id;
end
$$;

create function public.jobtrail_save_agenda(
    p_id uuid, p_create boolean, p_application_id uuid, p_type text,
    p_scheduled_at timestamptz, p_location_or_link text, p_notes text default ''
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    actor uuid := jobtrail_private.require_user();
    saved public.agendas;
    previous_parent uuid;
    applied_on date;
    payload_hash bytea;
    replayed boolean := false;
begin
    if p_create is null or p_scheduled_at is null or not isfinite(p_scheduled_at) then
        raise exception using errcode = '22023', message = 'Invalid agenda input';
    end if;
    p_location_or_link := jobtrail_private.trim_text(p_location_or_link);
    if p_create then
        payload_hash := jobtrail_private.fingerprint(jsonb_build_array(
            p_application_id, p_type, p_scheduled_at at time zone 'UTC', p_location_or_link, p_notes
        ));
        -- A replay can refer to a former parent after the agenda has been moved.
        select * into saved from public.agendas where user_id = actor and id = p_id;
        if found then
            if saved.create_fingerprint <> payload_hash then
                raise exception using errcode = 'JT004', message = 'Create ID conflict';
            end if;
            return jsonb_build_object('id', p_id, 'replayed', true);
        end if;
    else
        select application_id into previous_parent from public.agendas
        where user_id = actor and id = p_id;
        if not found then
            raise exception using errcode = 'JT001', message = 'Record unavailable';
        end if;
    end if;

    -- Lock parents before touching the agenda, in stable order for a move.
    perform id from public.applications
    where user_id = actor and id in (p_application_id, previous_parent)
    order by id for update;
    select a.applied_on into applied_on from public.applications as a
    where a.user_id = actor and a.id = p_application_id;
    if not found then
        raise exception using errcode = 'JT001', message = 'Record unavailable';
    end if;
    if jobtrail_private.wib_date(p_scheduled_at) < applied_on then
        raise exception using errcode = '22023', message = 'Agenda predates application';
    end if;

    if p_create then
        insert into public.agendas (id, user_id, application_id, type, scheduled_at,
            location_or_link, notes, create_fingerprint)
        values (p_id, actor, p_application_id, p_type, p_scheduled_at, p_location_or_link, p_notes,
            payload_hash)
        on conflict (id) do nothing;
        if not found then
            select * into saved from public.agendas where user_id = actor and id = p_id;
            if not found or saved.create_fingerprint <> payload_hash then
                raise exception using errcode = 'JT004', message = 'Create ID conflict';
            end if;
            replayed := true;
        end if;
    else
        update public.agendas set application_id = p_application_id, type = p_type,
            scheduled_at = p_scheduled_at, location_or_link = p_location_or_link, notes = p_notes
        where user_id = actor and id = p_id and application_id = previous_parent;
        if not found then
            raise exception using errcode = '40001', message = 'Agenda changed or was removed';
        end if;
    end if;
    return jsonb_build_object('id', p_id, 'replayed', replayed);
end
$$;

create function public.jobtrail_delete_agenda(p_id uuid) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
    actor uuid := jobtrail_private.require_user();
begin
    delete from public.agendas where user_id = actor and id = p_id;
    if not found then
        raise exception using errcode = 'JT001', message = 'Record unavailable';
    end if;
    return p_id;
end
$$;

create function public.jobtrail_save_document(
    p_id uuid, p_create boolean, p_title text, p_category text,
    p_file_name text, p_version text, p_notes text default ''
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
    actor uuid := jobtrail_private.require_user();
    saved public.documents;
    payload_hash bytea;
    replayed boolean := false;
begin
    if p_create is null then
        raise exception using errcode = '22023', message = 'Document write mode required';
    end if;
    p_title := jobtrail_private.trim_text(p_title);
    p_file_name := jobtrail_private.trim_text(p_file_name);
    p_version := jobtrail_private.trim_text(p_version);
    if p_create then
        payload_hash := jobtrail_private.fingerprint(jsonb_build_array(
            p_title, p_category, p_file_name, p_version, p_notes
        ));
        insert into public.documents (id, user_id, title, category, file_name, version, notes,
            create_fingerprint)
        values (p_id, actor, p_title, p_category, p_file_name, p_version, p_notes, payload_hash)
        on conflict (id) do nothing returning * into saved;
        if not found then
            select * into saved from public.documents where user_id = actor and id = p_id;
            if not found or saved.create_fingerprint <> payload_hash then
                raise exception using errcode = 'JT004', message = 'Create ID conflict';
            end if;
            replayed := true;
        end if;
    else
        update public.documents set title = p_title, category = p_category, file_name = p_file_name,
            version = p_version, notes = p_notes, updated_at = greatest(statement_timestamp(), updated_at)
        where user_id = actor and id = p_id returning * into saved;
        if not found then
            raise exception using errcode = 'JT001', message = 'Record unavailable';
        end if;
    end if;
    return jsonb_build_object('id', p_id, 'updated_at', saved.updated_at, 'replayed', replayed);
end
$$;

create function public.jobtrail_delete_document(p_id uuid) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
    actor uuid := jobtrail_private.require_user();
begin
    delete from public.documents where user_id = actor and id = p_id;
    if not found then
        raise exception using errcode = 'JT001', message = 'Record unavailable';
    end if;
    return p_id;
exception when foreign_key_violation then
    raise exception using errcode = 'JT005', message = 'Document is linked to an application';
end
$$;

create function public.jobtrail_load_snapshot() returns jsonb
language sql stable security invoker set search_path = ''
as $$
    select jsonb_build_object(
        'reference_instant', statement_timestamp(),
        'reference_date', (statement_timestamp() at time zone interval '+07:00')::date,
        'applications', coalesce((select jsonb_agg(to_jsonb(a) order by a.applied_on desc, a.id)
            from (select id, company, position, source, applied_on, status, location, work_type,
                salary_monthly_idr::text as salary_monthly_idr, notes, revision
                from public.applications) as a), '[]'::jsonb),
        'agendas', coalesce((select jsonb_agg(to_jsonb(a) order by a.scheduled_at, a.id)
            from (select id, application_id, type, scheduled_at, location_or_link, notes
                from public.agendas) as a), '[]'::jsonb),
        'history', coalesce((select jsonb_agg(to_jsonb(h) order by h.application_id, h.event_no)
            from (select id, application_id, status, changed_at, event_no
                from public.application_status_history) as h), '[]'::jsonb),
        'documents', coalesce((select jsonb_agg(to_jsonb(d) order by d.updated_at desc, d.id)
            from (select id, title, category, file_name, version, updated_at, notes
                from public.documents) as d), '[]'::jsonb),
        'application_documents', coalesce((select jsonb_agg(to_jsonb(l)
                order by l.application_id, l.document_id)
            from (select application_id, document_id from public.application_documents) as l), '[]'::jsonb)
    );
$$;

-- Seal all RPCs in the same transaction in which they are created.
grant create on schema public to jobtrail_mutator;
do $$
declare
    rpc record;
begin
    for rpc in
        select p.oid::regprocedure as signature, p.prosecdef as mutation
        from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname in (
            'jobtrail_load_snapshot', 'jobtrail_create_application', 'jobtrail_update_application',
            'jobtrail_change_status', 'jobtrail_delete_application', 'jobtrail_save_agenda',
            'jobtrail_delete_agenda', 'jobtrail_save_document', 'jobtrail_delete_document'
        )
    loop
        execute format('revoke all on function %s from public, anon, authenticated, service_role',
            rpc.signature);
        execute format('grant execute on function %s to authenticated', rpc.signature);
        if rpc.mutation then
            execute format('alter function %s owner to jobtrail_mutator', rpc.signature);
        end if;
    end loop;
end
$$;
revoke create on schema public from jobtrail_mutator;
revoke jobtrail_mutator from current_user;

commit;
