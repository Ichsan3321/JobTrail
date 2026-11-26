import { randomUUID } from 'node:crypto';
import { mkdtemp, readFile, readdir, rmdir, unlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import assert from 'node:assert/strict';
import test from 'node:test';
import { hostedSession, runCli } from './hosted_fixtures.mjs';
import { cleanupRun, createRun, newManifest, validateManifest, verifyRun, withManifest } from './hosted_fixture_lifecycle.mjs';
import { FixtureError, PROFILES, PROJECT, makePlan, rowPayload } from './hosted_fixture_plan.mjs';

const run = 'a67c0fb4-a59c-4e05-adee-fc2542239125';
const owner = { id: '43f6ae10-4023-4de2-9e40-70851cfbbbef', email: 'test-b@example.com' };
const clock = { reference_date: '2026-11-23', reference_instant: '2026-11-22T17:00:00.000Z' };
const env = {
  JOBTRAIL_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_synthetic_test_key',
  JOBTRAIL_QA_PASSWORD: 'fixture-only-password',
  JOBTRAIL_QA_EMAIL: owner.email,
};
const snapshot = () => ({
  ...clock, entity_revision_version: 1,
  applications: [], agendas: [], documents: [], history: [], application_documents: [],
});
const clone = value => structuredClone(value);

async function localDirectory(t) {
  const dir = await mkdtemp(join(tmpdir(), 'jobtrail-fixtures-test-'));
  t.after(async () => {
    for (const file of await readdir(dir)) await unlink(join(dir, file));
    await rmdir(dir);
  });
  return dir;
}
function localSession() {
  const data = snapshot();
  const calls = [];
  let fail;
  let identity = owner;
  function row(table, id) {
    return data[table].find(item => item.id === id);
  }
  function apply(name, args) {
    const table = name.includes('document') ? 'documents' :
      name.includes('agenda') ? 'agendas' : 'applications';
    if (name.startsWith('delete')) {
      assert.ok(row(table, args.p_id), 'Delete cannot target absent ID');
      assert.equal(args.p_expected_revision, row(table, args.p_id).revision);
      data[table] = data[table].filter(item => item.id !== args.p_id);
      if (table === 'applications') {
        data.history = data.history.filter(item => item.application_id !== args.p_id);
        data.application_documents = data.application_documents.filter(item => item.application_id !== args.p_id);
      }
      return args.p_id;
    }
    const replayed = Boolean(row(table, args.p_id));
    if (!replayed) {
      const saved = rowPayload({ args });
      data[table].push({ ...saved, revision: 1 });
      if (table === 'applications') {
        data.history.push({ id: randomUUID(), application_id: args.p_id, event_no: 1, status: args.p_status });
        for (const document_id of args.p_document_ids) {
          data.application_documents.push({ application_id: args.p_id, document_id });
        }
      }
    }
    return { id: args.p_id, replayed, revision: 1 };
  }
  return {
    data, calls,
    identity: async () => identity,
    setIdentity: value => { identity = value; },
    snapshot: async () => clone(data),
    ownerRow: async record => ({ ...row(record.table, record.id), user_id: owner.id }),
    setFailure: callback => { fail = callback; },
    async mutate(name, args) {
      calls.push([name, clone(args)]);
      return fail ? fail(name, args, () => apply(name, args)) : apply(name, args);
    },
  };
}
function persistence() {
  let value;
  return { get value() { return clone(value); }, persist: async next => { value = clone(next); } };
}
async function create(session, storage, profile = 'standard', manifest, settled = false) {
  return createRun(session, { manifest, runId: run, profile, persist: storage.persist, settled });
}

test('invalid config, non-disposable accounts and non-approved URLs stop offline', async () => {
  for (const input of [
    {}, { ...env, JOBTRAIL_QA_PASSWORD: ' ' },
    { ...env, JOBTRAIL_SUPABASE_PUBLISHABLE_KEY: 'sb_secret_synthetic' },
    { ...env, JOBTRAIL_QA_EMAIL: 'outside@example.invalid' },
    ...[PROJECT + '/', 'https://example.invalid', PROJECT + '.example.invalid', PROJECT + '@example.invalid',
      'http://ehzdmsdhdlqmicmwbnwh.supabase.co'].map(url => ({ ...env, JOBTRAIL_SUPABASE_URL: url })),
  ]) {
    const messages = [];
    let contacted = false;
    const code = await runCli(['create', '--profile', 'board', '--execute'], input, {
      fetchImpl() { contacted = true; throw new Error(); },
      out: message => messages.push(message), err: message => messages.push(message),
    });
    assert.equal(code, 1);
    assert.equal(contacted, false);
    assert.match(messages.join(' '), /\[FAIL\]/);
  }
});

test('no option defaults to check; dry-run create, verify and cleanup never call fetch', async t => {
  const directory = await localDirectory(t);
  await withManifest(directory, run, (_, persist) =>
    persist(newManifest(run, 'board', owner, snapshot())));
  const lines = [];
  const options = {
    directory,
    fetchImpl() { lines.push('FETCH'); throw new Error(); },
    out: value => lines.push(value), err: value => lines.push(value),
  };
  for (const args of [[], ['create', '--profile', 'standard'], ['verify', '--profile', 'empty'],
    ['verify', '--manifest', run], ['cleanup', '--manifest', run]]) {
    assert.equal(await runCli(args, env, options), 0);
  }
  assert.ok(lines.every(line => line.startsWith('[PASS] Dry-run')));
  assert.equal(await runCli(['verify', '--manifest', run, '--execute'], env, options), 1);
  assert.equal(await runCli(['cleanup', '--manifest', '../bad', '--execute'], env, options), 1);
  assert.equal(await runCli(['cleanup', '--manifest', run], { ...env, JOBTRAIL_QA_EMAIL: 'test-a@example.com' }, options), 1);
});

test('profiles derive compact stable expected values from WIB Monday, including period edges', () => {
  const { records, relationships, expected } = makePlan(run, 'standard', clock);
  assert.equal(records.length, 10);
  assert.equal(relationships.length, 1);
  assert.equal(expected.weekStartWib, '2026-11-23');
  assert.equal(expected.weeklyAchieved, 5);
  assert.equal(expected.weeklyProgressPct, 62.5);
  assert.equal(expected.upcomingInterviews, 1);
  assert.equal(expected.upcomingAgendas, 2);
  assert.deepEqual(Object.values(expected.periods.all.status), [1, 1, 1, 1, 1, 1]);
  assert.equal(records.find(record => record.label === 'prior-week').args.p_applied_on, '2026-11-22');
  const stats = makePlan(run, 'statistics', clock).expected.periods;
  assert.deepEqual([stats.all.total, stats['1m'].total, stats['2m'].total, stats['3m'].total], [7, 2, 4, 6]);
  assert.equal(stats['1m'].applicationsWithInterviewHistory, 1);
  assert.equal(stats['1m'].interviewEventsDenominator, 2);
  assert.equal(stats['1m'].interviewConversionPct, 50);
  const schedule = makePlan(run, 'schedule', clock).records;
  assert.match(schedule.find(record => record.label === 'wib-2359').args.p_scheduled_at, /T16:59:/);
  assert.match(schedule.find(record => record.label === 'wib-0001').args.p_scheduled_at, /T17:01:/);
  assert.ok(makePlan(run, 'form', clock).records.find(record => record.table === 'applications')
    .args.p_salary_monthly_idr === null);
  for (const profile of PROFILES.filter(value => value !== 'empty')) {
    const plan = makePlan(run, profile, clock);
    assert.deepEqual(plan, makePlan(run, profile, clock));
    assert.ok(plan.records.length <= 10);
    assert.ok(plan.records.every(record => record.marker === record.args.p_notes));
    const other = makePlan(randomUUID(), profile, clock);
    assert.ok(other.records.every(record => !plan.records.some(known => known.id === record.id)));
  }
});

test('manifest is private state, rejects tampered plans and prevents simultaneous resume', async t => {
  const dir = await localDirectory(t);
  const manifest = newManifest(run, 'board', { ...owner, password: env.JOBTRAIL_QA_PASSWORD }, snapshot());
  await withManifest(dir, run, async (previous, persist) => {
    assert.equal(previous, undefined);
    await persist(manifest);
    await assert.rejects(withManifest(dir, run, () => assert.fail()), /locked/);
  });
  const path = join(dir, run + '.json');
  const raw = await readFile(path, 'utf8');
  assert.ok(!raw.includes(env.JOBTRAIL_QA_PASSWORD));
  assert.deepEqual(validateManifest(JSON.parse(raw), run), manifest);
  const wrongOrigin = { ...manifest, project: 'https://example.invalid' };
  assert.throws(() => validateManifest(wrongOrigin, run), /identity or project/);
  const tampered = JSON.parse(raw);
  tampered.plan.records[0].args.p_company = 'Unrelated company';
  await writeFile(path, JSON.stringify(tampered), 'utf8');
  await assert.rejects(withManifest(dir, run, () => assert.fail()), /differs/);
});

test('writes are journaled on disk before dispatch and known partial writes resume safely', async t => {
  const dir = await localDirectory(t);
  const server = localSession();
  let count = 0;
  const rejected = Object.assign(new FixtureError('Known constraint failure.'), { definite: true });
  server.setFailure(async (name, args, apply) => {
    const recorded = JSON.parse(await readFile(join(dir, run + '.json'), 'utf8'));
    assert.equal(recorded.creates[args.p_id], 'IN_FLIGHT');
    assert.equal(recorded.plan.records.find(record => record.id === args.p_id).args.p_id, args.p_id);
    if (++count === 2) throw rejected;
    return apply();
  });
  await assert.rejects(withManifest(dir, run, (manifest, persist) =>
    createRun(server, { manifest, runId: run, profile: 'standard', persist })), /constraint/);
  const partial = JSON.parse(await readFile(join(dir, run + '.json'), 'utf8'));
  assert.equal(partial.creation, 'PARTIAL');
  assert.equal(partial.creates[server.calls[0][1].p_id], 'CONFIRMED');
  const failedCall = server.calls[1];
  assert.equal(partial.creates[failedCall[1].p_id], 'REJECTED');
  server.setFailure(undefined);
  const replay = await withManifest(dir, run, (manifest, persist) =>
    createRun(server, { manifest, runId: run, persist }));
  assert.equal(replay.status, 'PASS');
  assert.deepEqual(server.calls[2], failedCall);
  assert.equal(server.calls.filter(([, args]) => args.p_id === server.calls[0][1].p_id).length, 1);
});

test('ambiguous create can commit or fail; only settled same-manifest recovery can write', async () => {
  for (const commit of [true, false]) {
    const server = localSession();
    const storage = persistence();
    server.setFailure((_name, _args, apply) => {
      if (commit) apply();
      throw new FixtureError('Write outcome unknown.');
    });
    await assert.rejects(create(server, storage, 'board'), /unknown/);
    const first = server.calls[0];
    assert.equal(storage.value.creates[first[1].p_id], 'UNCERTAIN');
    assert.equal((await cleanupRun(server, storage.value, () => {})).status, 'PARTIAL CLEANUP');
    await assert.rejects(create(server, storage, 'board', storage.value), /reconcile/i);
    assert.equal(server.calls.length, 1);
    server.setFailure(undefined);
    assert.equal((await create(server, storage, 'board', storage.value, true)).status, 'PASS');
    if (!commit) assert.deepEqual(server.calls[1], first);
    else assert.equal(server.calls.filter(([, args]) => args.p_id === first[1].p_id).length, 1);
  }
});

test('owner mismatch fails before any lifecycle writes', async () => {
  const server = localSession();
  const storage = persistence();
  const manifest = newManifest(run, 'board', owner, snapshot());
  server.setIdentity({ ...owner, id: randomUUID() });
  await assert.rejects(verifyRun(server, manifest, storage.persist), /does not match/);
  await assert.rejects(cleanupRun(server, manifest, storage.persist), /does not match/);
  await assert.rejects(create(server, storage, 'board', manifest), /does not match/);
  assert.equal(server.calls.length, 0);
});

test('cleanup fails closed on mixed owners, changed markers, or outward dependencies', async () => {
  const variants = [
    server => { server.ownerRow = async () => ({ user_id: randomUUID() }); },
    server => { server.data.documents[0].notes = 'Not owned by the run'; },
    server => {
      server.data.application_documents.push({
        application_id: randomUUID(), document_id: server.data.documents[0].id,
      });
    },
    server => {
      server.data.agendas.push({
        ...server.data.agendas[0], id: randomUUID(),
      });
    },
    server => { server.data.agendas[0].application_id = randomUUID(); },
  ];
  for (const makeUnsafe of variants) {
    const server = localSession();
    const storage = persistence();
    await create(server, storage, 'detail');
    makeUnsafe(server);
    const count = server.calls.length;
    const result = await cleanupRun(server, storage.value, storage.persist);
    assert.equal(result.status, 'FAIL');
    assert.match(result.reason, /refused/);
    assert.equal(server.calls.length, count);
  }
});

test('cleanup skips missing fixtures, uses current revision, and preserves unrelated records', async () => {
  const server = localSession();
  const storage = persistence();
  await create(server, storage, 'standard');
  const unrelated = { ...server.data.applications[0], id: randomUUID(), notes: 'Retain' };
  server.data.applications.push(unrelated);
  server.data.agendas.shift();
  server.data.applications[0].revision = 3;
  server.data.agendas[0].revision = 4;
  server.data.documents[0].revision = 5;
  const oldCallCount = server.calls.length;
  const report = await cleanupRun(server, storage.value, storage.persist);
  assert.deepEqual(report, { status: 'PASS', remaining: 0 });
  const deletes = server.calls.slice(oldCallCount);
  assert.deepEqual(deletes.map(([rpc]) => rpc), [
    ...Array(2).fill('delete_agenda'), ...Array(6).fill('delete_application'), 'delete_document',
  ]);
  assert.equal(deletes[2][1].p_expected_revision, 3);
  assert.equal(deletes[0][1].p_expected_revision, 4);
  assert.equal(deletes.at(-1)[1].p_expected_revision, 5);
  assert.deepEqual(server.data.applications, [unrelated]);
  assert.equal(server.data.history.length + server.data.application_documents.length, 0);
  assert.deepEqual(await cleanupRun(server, storage.value, storage.persist), report);
  await assert.rejects(create(server, storage, 'standard', storage.value), /cleanup attempt/);
});

test('existing v1 manifests remain readable, but writes require the migrated contract', async () => {
  const server = localSession();
  const storage = persistence();
  await create(server, storage, 'detail');
  const manifest = validateManifest(storage.value, run);
  assert.equal(manifest.version, 1);
  const oldCallCount = server.calls.length;
  delete server.data.entity_revision_version;
  for (const row of [...server.data.documents, ...server.data.agendas]) delete row.revision;
  assert.equal((await verifyRun(server, manifest, storage.persist)).status, 'PASS');
  await assert.rejects(create(server, storage, 'detail', manifest), /revision migration/);
  await assert.rejects(cleanupRun(server, manifest, storage.persist), /revision migration/);
  assert.equal(storage.value.cleanup, 'PENDING');
  assert.equal(server.calls.length, oldCallCount);

  server.data.entity_revision_version = 1;
  await assert.rejects(verifyRun(server, manifest, storage.persist), /Invalid snapshot rows/);
  for (const row of [...server.data.documents, ...server.data.agendas]) row.revision = 1;
  assert.deepEqual(await cleanupRun(server, manifest, storage.persist), { status: 'PASS', remaining: 0 });
});

test('cleanup stops on revision changes before dispatch and on server stale rejection', async () => {
  for (const changeBeforeDispatch of [true, false]) {
    const server = localSession();
    const storage = persistence();
    await create(server, storage, 'detail');
    const oldCallCount = server.calls.length;
    const agenda = server.data.agendas[0];
    if (changeBeforeDispatch) {
      let reads = 0;
      const read = server.snapshot;
      server.snapshot = () => {
        if (++reads === 2) agenda.revision++;
        return read();
      };
    } else {
      server.setFailure((rpc, args) => {
        assert.equal(rpc, 'delete_agenda');
        assert.equal(args.p_expected_revision, 1);
        agenda.revision++;
        throw Object.assign(new FixtureError('JT002'), { definite: true });
      });
    }
    const report = await cleanupRun(server, storage.value, storage.persist);
    assert.equal(report.status, changeBeforeDispatch ? 'FAIL' : 'PARTIAL CLEANUP');
    assert.equal(server.calls.length - oldCallCount, changeBeforeDispatch ? 0 : 1);
    assert.equal(server.data.agendas[0].revision, 2);
    assert.equal(server.data.documents.length, 1);
    assert.equal(server.data.applications.length, 2);
  }
});

test('ambiguous delete stays partial until reconciled, then verifies absence', async () => {
  const server = localSession();
  const storage = persistence();
  await create(server, storage, 'detail');
  server.setFailure((_name, _args, apply) => {
    apply();
    throw new FixtureError('Write outcome unknown.');
  });
  const partial = await cleanupRun(server, storage.value, storage.persist);
  assert.equal(partial.status, 'PARTIAL CLEANUP');
  assert.ok(Object.values(storage.value.deletes).includes('UNCERTAIN'));
  assert.match((await cleanupRun(server, storage.value, storage.persist)).reason, /reconcile/i);
  server.setFailure(undefined);
  assert.deepEqual(await cleanupRun(server, storage.value, storage.persist, { settled: true }),
    { status: 'PASS', remaining: 0 });
});

test('verification reports baseline drift and live account metrics without record text', async () => {
  const server = localSession();
  const storage = persistence();
  const initial = await create(server, storage, 'board');
  assert.equal(initial.status, 'PASS');
  server.data.applications[0].status = 'interview';
  server.data.applications[0].revision = 2;
  const report = await verifyRun(server, storage.value, storage.persist);
  assert.equal(report.status, 'FAIL');
  assert.deepEqual(report.changed, ['transition']);
  assert.deepEqual(report.applicationChecks[0], {
    label: 'transition', status: 'interview', revision: 2,
    history: [{ event: 1, status: 'screening' }],
  });
  assert.equal(report.accountNow.periods.all.status.interview, 2);
  assert.equal(storage.value.verification, 'FAIL');
  assert.ok(!JSON.stringify(report).includes(server.data.applications[0].company));
});

test('HTTP mock pins origin, rejects redirects, verifies identity, and redacts raw failures', async () => {
  const token = 'synthetic-access-token';
  const calls = [];
  const responses = [
    Response.json({ user: { id: owner.id }, access_token: token }),
    Response.json(owner),
    Response.json({ code: token, message: env.JOBTRAIL_QA_PASSWORD }, { status: 500 }),
  ];
  const config = { key: env.JOBTRAIL_SUPABASE_PUBLISHABLE_KEY, email: owner.email, password: env.JOBTRAIL_QA_PASSWORD };
  const session = await hostedSession(config, (url, options) => {
    calls.push([url, options]);
    return responses.shift();
  });
  assert.deepEqual(await session.identity(), owner);
  await assert.rejects(session.snapshot(), error => {
    assert.match(error.message, /Snapshot read: HTTP 500/);
    for (const secret of [token, config.password, config.key]) assert.ok(!error.message.includes(secret));
    return true;
  });
  assert.deepEqual(calls.map(([url, options]) => [url.origin, url.pathname, options.redirect]), [
    [PROJECT, '/auth/v1/token', 'error'],
    [PROJECT, '/auth/v1/user', 'error'],
    [PROJECT, '/rest/v1/rpc/jobtrail_load_snapshot', 'error'],
  ]);
  assert.equal(calls[0][1].headers.Authorization, undefined);
  assert.equal(calls[1][1].headers.Authorization, 'Bearer ' + token);
  assert.ok(calls.every(([, options]) => options.signal instanceof AbortSignal));
  assert.throws(() => session.mutate('change_status', {}), /rejected/);

  const badIdentity = await hostedSession(config, url => url.pathname.endsWith('/token')
    ? Response.json({ user: { id: owner.id }, access_token: token })
    : Response.json({ ...owner, email: 'test-a@example.com' }));
  await assert.rejects(badIdentity.identity(), /does not match/);
  const output = [];
  const code = await runCli(['verify', '--profile', 'empty', '--hosted-read'], env, {
    fetchImpl: () => { throw new Error(token + config.password); },
    out: message => output.push(message), err: message => output.push(message),
  });
  assert.equal(code, 1);
  assert.match(output.join(), /request failed/);
  assert.ok(!output.join().includes(token) && !output.join().includes(config.password));
});

test('opted-in CLI create, verify and cleanup share one durable run through fake HTTP', async t => {
  const directory = await localDirectory(t);
  const server = localSession();
  const output = [];
  const methods = [];
  const token = 'synthetic-cli-token';
  const exec = args => runCli(args, env, {
    directory,
    out: message => output.push(message),
    err: message => output.push(message),
    fetchImpl: async (url, options) => {
      assert.equal(url.origin, PROJECT);
      assert.equal(options.redirect, 'error');
      methods.push([url.pathname, options.method]);
      const endpoint = url.pathname.split('/').at(-1);
      if (endpoint === 'token') {
        return Response.json({ access_token: token, user: await server.identity() });
      }
      assert.equal(options.headers.Authorization, 'Bearer ' + token);
      if (endpoint === 'user') return Response.json(await server.identity());
      if (endpoint === 'jobtrail_load_snapshot') return Response.json(await server.snapshot());
      if (endpoint.startsWith('jobtrail_')) {
        return Response.json(await server.mutate(endpoint.slice(9), JSON.parse(options.body)));
      }
      assert.equal(options.method, 'GET');
      const id = url.searchParams.get('id').slice(3);
      return Response.json([await server.ownerRow({ id, table: endpoint })]);
    },
  });

  assert.equal(await exec(['create', '--profile', 'detail', '--execute']), 0, output.join());
  const runId = output.find(line => line.startsWith('Manifest run UUID: ')).split(': ').at(-1);
  assert.equal(await exec(['verify', '--manifest', runId, '--hosted-read']), 0, output.join());
  assert.equal(await exec(['cleanup', '--manifest', runId, '--execute']), 0, output.join());
  const manifest = JSON.parse(await readFile(join(directory, runId + '.json'), 'utf8'));
  assert.equal(manifest.creation, 'PASS');
  assert.equal(manifest.verification, 'PASS');
  assert.equal(manifest.cleanup, 'PASS');
  assert.equal(methods.filter(([path]) => path.endsWith('/user')).length, 3);
  assert.equal(server.data.applications.length + server.data.agendas.length + server.data.documents.length, 0);
  assert.ok(!output.join().includes(token));
});

test('empty-profile hosted-read mode reports counts only and uses no mutation RPC', async () => {
  for (const populated of [false, true]) {
    const state = snapshot();
    if (populated) state.applications.push({
      id: randomUUID(), company: 'private row text', revision: 1, applied_on: clock.reference_date, status: 'applied',
    });
    const paths = [];
    const output = [];
    const code = await runCli(['verify', '--profile', 'empty', '--hosted-read'], env, {
      fetchImpl: url => {
        paths.push(url.pathname);
        if (paths.length === 1) return Response.json({ access_token: 'synthetic', user: owner });
        if (paths.length === 2) return Response.json(owner);
        return Response.json(state);
      },
      out: message => output.push(message), err: message => output.push(message),
    });
    assert.equal(code, Number(populated));
    assert.deepEqual(paths, ['/auth/v1/token', '/auth/v1/user', '/rest/v1/rpc/jobtrail_load_snapshot']);
    assert.equal(JSON.parse(output[0]).counts.applications, Number(populated));
    assert.ok(!output.join().includes('private row text'));
  }
});
