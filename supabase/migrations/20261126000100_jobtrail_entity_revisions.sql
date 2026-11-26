begin;

alter table public.documents
    add column revision integer not null default 1,
    add constraint documents_revision_positive check (revision > 0);
alter table public.agendas
    add column revision integer not null default 1,
    add constraint agendas_revision_positive check (revision > 0);

grant select (revision) on public.documents, public.agendas to authenticated;
grant update (revision) on public.documents, public.agendas to jobtrail_mutator;

-- Replace, rather than overload, the old entry points. Save defaults preserve
-- create calls, but update cannot run without a matching positive revision.
-- The migration role needs ownership privileges to drop the old mutator RPCs.
grant jobtrail_mutator to current_user;
drop function public.jobtrail_save_agenda(uuid, boolean, uuid, text, timestamptz, text, text);
drop function public.jobtrail_save_document(uuid, boolean, text, text, text, text, text);
drop function public.jobtrail_delete_agenda(uuid);
drop function public.jobtrail_delete_document(uuid);

create function public.jobtrail_save_agenda(
    p_id uuid, p_create boolean, p_application_id uuid, p_type text,
    p_scheduled_at timestamptz, p_location_or_link text, p_notes text default '',
    p_expected_revision integer default null
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
    if p_create is null then
        raise exception using errcode = '22023', message = 'Agenda write mode required';
    end if;
    p_location_or_link := jobtrail_private.trim_text(p_location_or_link);
    if p_create then
        if p_expected_revision is not null or p_scheduled_at is null or not isfinite(p_scheduled_at) then
            raise exception using errcode = '22023', message = 'Invalid agenda create input';
        end if;
        payload_hash := jobtrail_private.fingerprint(jsonb_build_array(
            p_application_id, p_type, p_scheduled_at at time zone 'UTC', p_location_or_link, p_notes
        ));
        -- A replay can refer to a former parent after the agenda has been moved.
        select * into saved from public.agendas where user_id = actor and id = p_id;
        if found then
            if saved.create_fingerprint <> payload_hash then
                raise exception using errcode = 'JT004', message = 'Create ID conflict';
            end if;
            return jsonb_build_object('id', saved.id, 'revision', saved.revision, 'replayed', true);
        end if;
    else
        select application_id into previous_parent from public.agendas
        where user_id = actor and id = p_id;
        if not found then
            raise exception using errcode = 'JT001', message = 'Record unavailable';
        end if;
    end if;

    -- Lock parents first and in stable order, as in the original agenda RPC.
    perform id from public.applications
    where user_id = actor and id in (p_application_id, previous_parent)
    order by id for update;

    if not p_create then
        select * into saved from public.agendas where user_id = actor and id = p_id for update;
        if not found then
            raise exception using errcode = 'JT001', message = 'Record unavailable';
        end if;
        if p_expected_revision is distinct from saved.revision or saved.application_id <> previous_parent then
            raise exception using errcode = 'JT002', message = 'Stale agenda revision';
        end if;
    end if;
    if p_scheduled_at is null or not isfinite(p_scheduled_at) then
        raise exception using errcode = '22023', message = 'Invalid agenda date';
    end if;
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
        values (p_id, actor, p_application_id, p_type, p_scheduled_at, p_location_or_link,
            p_notes, payload_hash)
        on conflict (id) do nothing returning * into saved;
        if not found then
            select * into saved from public.agendas where user_id = actor and id = p_id;
            if not found or saved.create_fingerprint <> payload_hash then
                raise exception using errcode = 'JT004', message = 'Create ID conflict';
            end if;
            replayed := true;
        end if;
    else
        -- An accepted full save consumes one revision even for identical fields.
        update public.agendas set application_id = p_application_id, type = p_type,
            scheduled_at = p_scheduled_at, location_or_link = p_location_or_link,
            notes = p_notes, revision = revision + 1
        where user_id = actor and id = p_id returning * into saved;
    end if;
    return jsonb_build_object('id', saved.id, 'revision', saved.revision, 'replayed', replayed);
end
$$;

create function public.jobtrail_save_document(
    p_id uuid, p_create boolean, p_title text, p_category text, p_file_name text,
    p_version text, p_notes text default '', p_expected_revision integer default null
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
        if p_expected_revision is not null then
            raise exception using errcode = '22023', message = 'Document create cannot specify a revision';
        end if;
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
        select * into saved from public.documents where user_id = actor and id = p_id for update;
        if not found then
            raise exception using errcode = 'JT001', message = 'Record unavailable';
        end if;
        if p_expected_revision is distinct from saved.revision then
            raise exception using errcode = 'JT002', message = 'Stale document revision';
        end if;
        update public.documents set title = p_title, category = p_category, file_name = p_file_name,
            version = p_version, notes = p_notes, updated_at = greatest(statement_timestamp(), updated_at),
            revision = revision + 1
        where user_id = actor and id = p_id returning * into saved;
    end if;
    return jsonb_build_object('id', saved.id, 'updated_at', saved.updated_at,
        'revision', saved.revision, 'replayed', replayed);
end
$$;

create function public.jobtrail_delete_agenda(p_id uuid, p_expected_revision integer)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
    actor uuid := jobtrail_private.require_user();
    current_revision integer;
begin
    select revision into current_revision from public.agendas
    where user_id = actor and id = p_id for update;
    if not found then
        raise exception using errcode = 'JT001', message = 'Record unavailable';
    end if;
    if p_expected_revision is distinct from current_revision then
        raise exception using errcode = 'JT002', message = 'Stale agenda revision';
    end if;
    delete from public.agendas where user_id = actor and id = p_id;
    return p_id;
end
$$;

create function public.jobtrail_delete_document(p_id uuid, p_expected_revision integer)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
    actor uuid := jobtrail_private.require_user();
    current_revision integer;
begin
    select revision into current_revision from public.documents
    where user_id = actor and id = p_id for update;
    if not found then
        raise exception using errcode = 'JT001', message = 'Record unavailable';
    end if;
    if p_expected_revision is distinct from current_revision then
        raise exception using errcode = 'JT002', message = 'Stale document revision';
    end if;
    delete from public.documents where user_id = actor and id = p_id;
    return p_id;
exception when foreign_key_violation then
    raise exception using errcode = 'JT005', message = 'Document is linked to an application';
end
$$;

create or replace function public.jobtrail_load_snapshot() returns jsonb
language sql stable security invoker set search_path = ''
as $$
    select jsonb_build_object(
        'entity_revision_version', 1,
        'reference_instant', statement_timestamp(),
        'reference_date', (statement_timestamp() at time zone interval '+07:00')::date,
        'applications', coalesce((select jsonb_agg(to_jsonb(a) order by a.applied_on desc, a.id)
            from (select id, company, position, source, applied_on, status, location, work_type,
                salary_monthly_idr::text as salary_monthly_idr, notes, revision
                from public.applications) as a), '[]'::jsonb),
        'agendas', coalesce((select jsonb_agg(to_jsonb(a) order by a.scheduled_at, a.id)
            from (select id, application_id, type, scheduled_at, location_or_link, notes, revision
                from public.agendas) as a), '[]'::jsonb),
        'history', coalesce((select jsonb_agg(to_jsonb(h) order by h.application_id, h.event_no)
            from (select id, application_id, status, changed_at, event_no
                from public.application_status_history) as h), '[]'::jsonb),
        'documents', coalesce((select jsonb_agg(to_jsonb(d) order by d.updated_at desc, d.id)
            from (select id, title, category, file_name, version, updated_at, notes, revision
                from public.documents) as d), '[]'::jsonb),
        'application_documents', coalesce((select jsonb_agg(to_jsonb(l)
                order by l.application_id, l.document_id)
            from (select application_id, document_id from public.application_documents) as l), '[]'::jsonb)
    );
$$;

-- Seal the new signatures before commit. The snapshot retains its previous ACL.
grant create on schema public to jobtrail_mutator;
do $$
declare
    signature regprocedure;
begin
    foreach signature in array array[
        'public.jobtrail_save_agenda(uuid,boolean,uuid,text,timestamptz,text,text,integer)'::regprocedure,
        'public.jobtrail_save_document(uuid,boolean,text,text,text,text,text,integer)'::regprocedure,
        'public.jobtrail_delete_agenda(uuid,integer)'::regprocedure,
        'public.jobtrail_delete_document(uuid,integer)'::regprocedure
    ] loop
        execute format('revoke all on function %s from public, anon, authenticated, service_role', signature);
        execute format('grant execute on function %s to authenticated', signature);
        execute format('alter function %s owner to jobtrail_mutator', signature);
    end loop;
end
$$;
revoke create on schema public from jobtrail_mutator;
revoke jobtrail_mutator from current_user;

notify pgrst, 'reload schema';
commit;
