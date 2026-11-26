-- Run against the migrated disposable database seeded by run_entity_revision_tests.py.
\set ON_ERROR_STOP on
begin;
set local timezone = 'America/Los_Angeles';

create function pg_temp.check_revision(actual boolean, context text) returns void
language plpgsql as $$
begin
    if actual is distinct from true then raise exception 'Assertion failed: %', context; end if;
end
$$;

create function pg_temp.reject(command text, expected text) returns void
language plpgsql as $$
begin
    begin
        execute command;
    exception when others then
        if sqlstate = expected then return; end if;
        raise exception 'Expected %, got % (%)', expected, sqlstate, sqlerrm;
    end;
    raise exception 'Expected %, but SQL succeeded', expected;
end
$$;

select pg_temp.check_revision(
    to_regprocedure('public.jobtrail_save_document(uuid,boolean,text,text,text,text,text)') is null
    and to_regprocedure('public.jobtrail_save_agenda(uuid,boolean,uuid,text,timestamptz,text,text)') is null
    and to_regprocedure('public.jobtrail_delete_document(uuid)') is null
    and to_regprocedure('public.jobtrail_delete_agenda(uuid)') is null,
    'legacy signatures removed; no overload can bypass the guard');
select pg_temp.reject(
    $$update public.documents set revision = 0 where id = '73000000-0000-4000-8000-000000000001'$$, '23514');
select pg_temp.reject(
    $$update public.agendas set revision = 0 where id = '74000000-0000-4000-8000-000000000001'$$, '23514');

set local role anon;
select pg_temp.reject(
    $$select public.jobtrail_delete_document('73000000-0000-4000-8000-000000000001',1)$$, '42501');
select pg_temp.reject(
    $$select public.jobtrail_save_agenda('74000000-0000-4000-8000-000000000001',false,
        '72000000-0000-4000-8000-000000000001','test','2025-06-15 00:00:00+07','room','',1)$$, '42501');
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"71000000-0000-4000-8000-000000000001"}', true);
do $$
declare
    app constant uuid := '72000000-0000-4000-8000-000000000001';
    other_app constant uuid := '72000000-0000-4000-8000-000000000002';
    move_target constant uuid := '72000000-0000-4000-8000-000000000003';
    doc constant uuid := '73000000-0000-4000-8000-000000000001';
    other_doc constant uuid := '73000000-0000-4000-8000-000000000002';
    agenda constant uuid := '74000000-0000-4000-8000-000000000001';
    other_agenda constant uuid := '74000000-0000-4000-8000-000000000002';
    new_doc constant uuid := '73000000-0000-4000-8000-000000000003';
    new_agenda constant uuid := '74000000-0000-4000-8000-000000000003';
    missing constant uuid := '75000000-0000-4000-8000-000000000001';
    blocked_id uuid;
    snapshot jsonb;
    receipt jsonb;
begin
    snapshot := public.jobtrail_load_snapshot();
    perform pg_temp.check_revision(snapshot->>'entity_revision_version' = '1'
        and jsonb_array_length(snapshot->'documents') = 1
        and jsonb_array_length(snapshot->'agendas') = 1
        and snapshot#>>'{documents,0,revision}' = '1' and snapshot#>>'{documents,0,title}' = 'Original CV'
        and snapshot#>>'{agendas,0,revision}' = '1' and snapshot#>>'{agendas,0,location_or_link}' = 'Original room'
        and snapshot#>>'{applications,0,revision}' = '1', 'backfill and owner-scoped snapshot');
    perform pg_temp.check_revision((public.jobtrail_save_document(new_doc, true, 'New',
        'portfolio', 'new.pdf', '1')->>'revision')::integer = 1, 'new document revision one');
    perform pg_temp.check_revision((public.jobtrail_save_agenda(new_agenda, true, app, 'interview',
        '2025-06-15 00:00:00+07', 'New room')->>'revision')::integer = 1, 'new agenda revision one');

    perform pg_temp.reject(format('update public.documents set revision = 99 where id = %L', doc), '42501');
    perform pg_temp.reject(format('delete from public.agendas where id = %L', agenda), '42501');
    perform pg_temp.reject(format('select public.jobtrail_delete_document(%L)', doc), '42883');
    perform pg_temp.reject(format('select public.jobtrail_delete_agenda(%L)', agenda), '42883');
    perform pg_temp.reject(format('select public.jobtrail_save_document(%L,false,%L,%L,%L,%L)',
        doc, 'Legacy edit', 'cv_resume', 'original.pdf', '1'), 'JT002');
    perform pg_temp.reject(format('select public.jobtrail_save_agenda(%L,false,%L,%L,%L,%L)',
        agenda, app, 'test', '2025-06-15 00:00:00+07', 'Legacy edit'), 'JT002');

    foreach blocked_id in array array[other_doc, missing] loop
        perform pg_temp.reject(format('select public.jobtrail_delete_document(%L,1)', blocked_id), 'JT001');
        perform pg_temp.reject(format('select public.jobtrail_save_document(%L,false,%L,%L,%L,%L,'''',1)',
            blocked_id, 'Other edit', 'cv_resume', 'original.pdf', '1'), 'JT001');
    end loop;
    foreach blocked_id in array array[other_agenda, missing] loop
        perform pg_temp.reject(format('select public.jobtrail_delete_agenda(%L,1)', blocked_id), 'JT001');
        perform pg_temp.reject(format('select public.jobtrail_save_agenda(%L,false,%L,%L,%L,%L,'''',1)',
            blocked_id, app, 'test', '2025-06-15 00:00:00+07', 'Other edit'), 'JT001');
    end loop;
    perform pg_temp.reject(format('select public.jobtrail_save_agenda(%L,false,%L,%L,%L,%L,'''',1)',
        agenda, other_app, 'test', '2025-06-15 00:00:00+07', 'Cross-account move'), 'JT001');
    perform pg_temp.reject(format('select public.jobtrail_save_agenda(%L,false,%L,%L,%L,%L,'''',1)',
        agenda, app, 'test', '2025-06-14 16:59:59.999999+00', 'Too early'), '22023');

    receipt := public.jobtrail_save_document(doc, false, 'Winner CV', 'cv_resume', 'original.pdf', '1',
        p_expected_revision => 1);
    perform pg_temp.check_revision(receipt->>'id' = doc::text and receipt->>'revision' = '2'
        and receipt ? 'updated_at' and receipt->>'replayed' = 'false', 'document update receipt');
    receipt := public.jobtrail_save_agenda(agenda, false, app, 'test', '2025-06-15 00:00:00+07',
        'Winner room', p_expected_revision => 1);
    perform pg_temp.check_revision(receipt->>'id' = agenda::text and receipt->>'revision' = '2'
        and receipt->>'replayed' = 'false', 'agenda update receipt and WIB boundary');
    perform pg_temp.reject(format('select public.jobtrail_save_document(%L,false,%L,%L,%L,%L,'''',1)',
        doc, 'Stale edit', 'cv_resume', 'original.pdf', '1'), 'JT002');
    perform pg_temp.reject(format('select public.jobtrail_save_agenda(%L,false,%L,%L,%L,%L,'''',1)',
        agenda, app, 'interview', '2025-06-15 00:00:00+07', 'Stale edit'), 'JT002');
    perform pg_temp.reject(format('select public.jobtrail_delete_document(%L,1)', doc), 'JT002');
    perform pg_temp.reject(format('select public.jobtrail_delete_agenda(%L,1)', agenda), 'JT002');
    perform pg_temp.reject(format('select public.jobtrail_delete_document(%L,null)', doc), 'JT002');
    perform pg_temp.reject(format('select public.jobtrail_delete_agenda(%L,0)', agenda), 'JT002');

    receipt := public.jobtrail_save_document(doc, true, 'Original CV', 'cv_resume', 'original.pdf', '1');
    perform pg_temp.check_revision(receipt->>'revision' = '2' and receipt->>'replayed' = 'true'
        and (select title = 'Winner CV' from public.documents where id = doc),
        'pre-migration document fingerprint still replays without overwrite');
    receipt := public.jobtrail_save_agenda(agenda, true, app, 'interview', '2025-06-14 17:00:00+00',
        'Original room');
    perform pg_temp.check_revision(receipt->>'revision' = '2' and receipt->>'replayed' = 'true'
        and (select type = 'test' and location_or_link = 'Winner room' from public.agendas where id = agenda),
        'pre-migration agenda fingerprint still replays across offset without overwrite');
    perform pg_temp.check_revision(public.jobtrail_save_document(doc, false, 'Winner CV',
        'cv_resume', 'original.pdf', '1', p_expected_revision => 2)->>'revision' = '3',
        'identical document full save consumes one revision');
    perform pg_temp.check_revision(public.jobtrail_save_agenda(agenda, false, app, 'test',
        '2025-06-15 00:00:00+07', 'Winner room', p_expected_revision => 2)->>'revision' = '3',
        'identical agenda full save consumes one revision');
    perform pg_temp.reject(format('select public.jobtrail_delete_document(%L,3)', doc), 'JT005');
    perform pg_temp.check_revision(public.jobtrail_delete_agenda(new_agenda, 1) = new_agenda
        and public.jobtrail_delete_document(new_doc, 1) = new_doc, 'guarded delete receipts');

    perform public.jobtrail_create_application(move_target, 'Move target', 'Engineer', 'Website',
        '2025-06-15', 'applied', 'Surabaya', 'hybrid');
    perform pg_temp.check_revision(public.jobtrail_save_agenda(agenda, false, move_target, 'test',
        '2025-06-15 00:00:00+07', 'New parent room', p_expected_revision => 3)->>'revision' = '4',
        'move to another owned lamaran advances the revision');
    receipt := public.jobtrail_save_agenda(agenda, true, app, 'interview', '2025-06-14 17:00:00+00',
        'Original room');
    perform pg_temp.check_revision(receipt->>'revision' = '4' and receipt->>'replayed' = 'true'
        and (select application_id = move_target from public.agendas where id = agenda),
        'create replay keeps the new parent');
    perform public.jobtrail_delete_application(app, 1);
    perform public.jobtrail_delete_application(move_target, 1);
    perform pg_temp.check_revision(not exists (select id from public.agendas where id = agenda)
        and exists (select id from public.documents where id = doc and revision = 3),
        'application cascade removes agenda and retains linked metadata');
end
$$;
rollback;
\echo 'JobTrail entity revision migration and RPC assertions passed'
