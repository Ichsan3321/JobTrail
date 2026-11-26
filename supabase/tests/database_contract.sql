-- Run with psql -X -v ON_ERROR_STOP=1 on a disposable local database.
-- All fixtures and test changes are rolled back.
begin;
set local timezone = 'America/Los_Angeles';

create function pg_temp.assert_true(actual boolean, context text) returns void
language plpgsql as $$
begin
    if actual is distinct from true then
        raise exception 'Assertion failed: %', context;
    end if;
end
$$;

create function pg_temp.expect_error(command text, expected_state text) returns void
language plpgsql as $$
begin
    begin
        execute command;
    exception when others then
        if sqlstate <> expected_state then
            raise exception 'Expected %, received % (%): %', expected_state, sqlstate, sqlerrm, command;
        end if;
        return;
    end;
    raise exception 'Expected %, statement succeeded: %', expected_state, command;
end
$$;

create function pg_temp.create_example(p_id uuid, p_links uuid[] default '{}',
    p_company text default 'Example Company') returns jsonb
language sql as $$
    select public.jobtrail_create_application(p_id, p_company, 'Engineer', 'Situs perusahaan',
        date '2025-06-15', 'screening', 'Surabaya', 'hybrid',
        p_salary_monthly_idr => 9007199254740993, p_document_ids => p_links);
$$;

insert into auth.users (id) values
    ('10000000-0000-4000-8000-000000000001'),
    ('10000000-0000-4000-8000-000000000002');

select pg_temp.assert_true(
    (select count(*) = 5 and bool_and(relrowsecurity and relforcerowsecurity)
     from pg_class where oid in ('public.applications'::regclass, 'public.agendas'::regclass,
         'public.application_status_history'::regclass, 'public.documents'::regclass,
         'public.application_documents'::regclass)),
    'every application table enables and forces RLS');
select pg_temp.assert_true(
    (select not (rolsuper or rolbypassrls or rolcanlogin or rolinherit) from pg_roles
     where rolname = 'jobtrail_mutator')
    and not pg_has_role('authenticated', 'jobtrail_mutator', 'MEMBER')
    and not has_schema_privilege('jobtrail_mutator', 'public', 'CREATE')
    and not has_schema_privilege('jobtrail_mutator', 'auth', 'USAGE'),
    'function owner is isolated');
select pg_temp.assert_true(
    (select count(*) = 8 and bool_and(prosecdef and pg_get_userbyid(proowner) = 'jobtrail_mutator'
         and proconfig = array['search_path=""'])
     from pg_proc where pronamespace = 'public'::regnamespace and proname like 'jobtrail_%'
         and proname <> 'jobtrail_load_snapshot'),
    'mutations run under the restricted role with a fixed path');

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select pg_temp.expect_error('select id from public.applications', '42501');
select pg_temp.expect_error('select public.jobtrail_load_snapshot()', '42501');
select pg_temp.expect_error(
    $$select pg_temp.create_example('20000000-0000-4000-8000-000000000001')$$, '42501');
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"10000000-0000-4000-8000-000000000002"}', true);
select public.jobtrail_save_document('30000000-0000-4000-8000-000000000002', true,
    'Other CV', 'cv_resume', 'other.pdf', '1');
select pg_temp.create_example('20000000-0000-4000-8000-000000000002');
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"10000000-0000-4000-8000-000000000001"}', true);
do $$
declare
    app_id constant uuid := '20000000-0000-4000-8000-000000000001';
    other_app constant uuid := '20000000-0000-4000-8000-000000000002';
    bad_id constant uuid := '20000000-0000-4000-8000-000000000003';
    doc_id constant uuid := '30000000-0000-4000-8000-000000000001';
    foreign_doc constant uuid := '30000000-0000-4000-8000-000000000002';
    agenda_id constant uuid := '40000000-0000-4000-8000-000000000001';
    snapshot jsonb;
begin
    perform pg_temp.assert_true(not exists (select id from public.applications)
        and not exists (select id from public.documents)
        and not exists (select id from public.application_status_history), 'other owner is invisible');
    perform pg_temp.expect_error(format('select public.jobtrail_change_status(%L,1,%L)',
        other_app, 'interview'), 'JT001');
    perform pg_temp.expect_error(format('select public.jobtrail_delete_application(%L,1)', other_app), 'JT001');
    perform pg_temp.expect_error(format('select public.jobtrail_delete_document(%L,1)', foreign_doc), 'JT001');
    perform pg_temp.expect_error(format('select public.jobtrail_save_agenda(%L,true,%L,%L,%L,%L)',
        agenda_id, other_app, 'test', '2025-06-15T00:00:00+07:00', 'Office'), 'JT001');
    perform pg_temp.expect_error(format('select pg_temp.create_example(%L)', other_app), 'JT004');

    perform public.jobtrail_save_document(doc_id, true, 'My CV', 'cv_resume', 'resume.pdf', '1');
    perform public.jobtrail_save_document(doc_id, false, 'My revised CV', 'cv_resume', 'resume.pdf', '2',
        p_expected_revision => 1);
    perform pg_temp.assert_true((public.jobtrail_save_document(doc_id, true, 'My CV', 'cv_resume',
        'resume.pdf', '1')->>'replayed')::boolean
        and (select title = 'My revised CV' from public.documents where id = doc_id), 'document create replay');
    perform pg_temp.expect_error(format('select pg_temp.create_example(%L,%L::uuid[])',
        bad_id, array[doc_id, foreign_doc]), 'JT003');
    perform pg_temp.assert_true(not exists (select id from public.applications where id = bad_id)
        and not exists (select application_id from public.application_documents where application_id = bad_id)
        and not exists (select id from public.application_status_history where application_id = bad_id),
        'invalid link rolls back the full create');
    perform pg_temp.expect_error(format('select pg_temp.create_example(%L,%L::uuid[])',
        bad_id, array[doc_id, doc_id]), '22023');

    perform pg_temp.assert_true((pg_temp.create_example(app_id, array[doc_id], ' Example Company ')
        ->>'revision')::integer = 1, 'create returns revision one');
    perform pg_temp.assert_true((pg_temp.create_example(app_id, array[doc_id])
        ->>'replayed')::boolean, 'canonical create retry');
    perform pg_temp.expect_error(format('select pg_temp.create_example(%L,%L::uuid[],%L)',
        app_id, array[doc_id], 'Conflicting Company'), 'JT004');
    perform pg_temp.assert_true(
        (select count(*) = 1 and bool_and(event_no = 1 and status = 'screening')
         from public.application_status_history where application_id = app_id), 'initial history exactly once');

    perform pg_temp.expect_error('insert into public.documents (title) values (''direct'')', '42501');
    perform pg_temp.expect_error('update public.applications set user_id = null', '42501');
    perform pg_temp.expect_error('update public.application_status_history set status = ''applied''', '42501');
    perform pg_temp.expect_error('delete from public.application_documents', '42501');
    perform pg_temp.expect_error('select create_fingerprint from public.applications', '42501');

    perform pg_temp.expect_error(format('select public.jobtrail_save_agenda(%L,true,%L,%L,%L,%L)',
        agenda_id, app_id, 'interview', '2025-06-14 16:59:59.999999+00', 'Office'), '22023');
    perform public.jobtrail_save_agenda(agenda_id, true, app_id, 'interview',
        '2025-06-14 17:00:00+00', 'Office');
    perform pg_temp.assert_true((public.jobtrail_save_agenda(agenda_id, true, app_id, 'interview',
        '2025-06-15 00:00:00+07', 'Office')->>'replayed')::boolean, 'same instant replays across offsets');
    perform public.jobtrail_save_agenda(agenda_id, false, app_id, 'test',
        '2025-06-15 01:00:00+07', 'Updated office', p_expected_revision => 1);
    perform pg_temp.assert_true((select type = 'test' and location_or_link = 'Updated office'
        from public.agendas where id = agenda_id), 'owner can edit agenda');
    perform pg_temp.expect_error(format(
        'select public.jobtrail_update_application(%L,1,%L,%L,%L,%L,%L,%L,%L,null,'''',''{}'')',
        app_id, 'Changed', 'Engineer', 'Situs perusahaan', '2025-06-16', 'screening', 'Surabaya', 'hybrid'), '22023');
    perform pg_temp.expect_error(format(
        'select public.jobtrail_create_application(%L,%L,%L,%L,%L,%L,%L,%L)',
        bad_id, 'Future', 'Engineer', 'LinkedIn', (statement_timestamp() at time zone interval '+07:00')::date + 1,
        'applied', 'Surabaya', 'hybrid'), '22023');

    perform pg_temp.expect_error(format(
        'select public.jobtrail_update_application(%L,1,%L,%L,%L,%L,%L,%L,%L,null,%L,%L::uuid[])',
        app_id, 'Should roll back', 'Engineer', 'LinkedIn', '2025-06-15', 'interview', 'Surabaya',
        'remote', '', array[foreign_doc]), 'JT003');
    perform pg_temp.assert_true(
        (select company = 'Example Company' and revision = 1 and status = 'screening'
         from public.applications where id = app_id)
        and (select count(*) = 1 from public.application_status_history where application_id = app_id)
        and (select document_id = doc_id from public.application_documents where application_id = app_id),
        'invalid update restores payload, revision, history and links');

    perform public.jobtrail_update_application(app_id, 1, 'Changed', 'Engineer', 'Website perusahaan',
        '2025-06-15', 'screening', 'Surabaya', 'remote', 9007199254740993, '', array[doc_id]);
    perform pg_temp.assert_true((public.jobtrail_change_status(app_id, 2, 'screening')->>'revision')::integer = 2
        and (select count(*) = 1 from public.application_status_history where application_id = app_id),
        'same-status full edit and status command add no history');
    perform pg_temp.expect_error(format('select public.jobtrail_change_status(%L,1,%L)',
        app_id, 'interview'), 'JT002');
    perform pg_temp.expect_error(format(
        'select public.jobtrail_update_application(%L,1,%L,%L,%L,%L,%L,%L,%L,null,'''',''{}'')',
        app_id, 'Stale', 'Engineer', 'LinkedIn', '2025-06-15', 'screening', 'Surabaya', 'remote'), 'JT002');
    perform public.jobtrail_change_status(app_id, 2, 'interview');
    perform public.jobtrail_change_status(app_id, 3, 'rejected');
    perform pg_temp.assert_true((select array_agg(status order by changed_at, event_no) =
        array['screening', 'interview', 'rejected'] from public.application_status_history
        where application_id = app_id), 'equal timestamps sort by event number');
    perform pg_temp.assert_true((pg_temp.create_example(app_id, array[doc_id])->>'revision')::integer = 4,
        'original create replay after edit does not overwrite');

    snapshot := public.jobtrail_load_snapshot();
    perform pg_temp.assert_true(
        snapshot #>> '{applications,0,source}' = 'Website perusahaan'
        and snapshot #>> '{applications,0,salary_monthly_idr}' = '9007199254740993'
        and jsonb_typeof(snapshot #> '{applications,0,salary_monthly_idr}') = 'string'
        and jsonb_array_length(snapshot->'applications') = 1
        and jsonb_array_length(snapshot->'documents') = 1
        and jsonb_array_length(snapshot->'agendas') = 1
        and jsonb_array_length(snapshot->'application_documents') = 1
        and jsonb_array_length(snapshot->'history') = 3
        and (snapshot->>'reference_date')::date =
            ((snapshot->>'reference_instant')::timestamptz at time zone interval '+07:00')::date,
        'snapshot is owner scoped, lossless and uses WIB');
    perform pg_temp.expect_error(format('select public.jobtrail_delete_document(%L,2)', doc_id), 'JT005');
    perform public.jobtrail_delete_agenda(agenda_id, 2);
    perform pg_temp.assert_true(not exists (select id from public.agendas), 'owner can delete agenda');
    perform public.jobtrail_save_agenda('40000000-0000-4000-8000-000000000002', true,
        app_id, 'test', '2025-06-15T02:00:00+07:00', 'Office');
    perform pg_temp.expect_error(format('select public.jobtrail_delete_application(%L,3)', app_id), 'JT002');
    perform public.jobtrail_delete_application(app_id, 4);
    perform pg_temp.assert_true(not exists (select id from public.applications)
        and not exists (select id from public.agendas)
        and not exists (select id from public.application_status_history)
        and not exists (select application_id from public.application_documents)
        and exists (select id from public.documents where id = doc_id), 'application cascade retains documents');
    perform public.jobtrail_delete_document(doc_id, 2);
end
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"10000000-0000-4000-8000-000000000002"}', true);
select pg_temp.assert_true((select count(id) = 1 from public.applications)
    and (select count(id) = 1 from public.documents), 'other account data remained intact');
select public.jobtrail_update_application('20000000-0000-4000-8000-000000000002', 1, 'Other company',
    'Engineer', 'Situs perusahaan', '2025-06-15', 'screening', 'Surabaya', 'hybrid', null, '',
    array['30000000-0000-4000-8000-000000000002']::uuid[]);
reset role;
delete from auth.users where id = '10000000-0000-4000-8000-000000000002';
select pg_temp.assert_true(not exists (select id from public.applications
    where user_id = '10000000-0000-4000-8000-000000000002')
    and not exists (select id from public.documents where user_id = '10000000-0000-4000-8000-000000000002'),
    'account deletion cascades even when documents are linked');
rollback;
\echo 'JobTrail database contract assertions passed'
