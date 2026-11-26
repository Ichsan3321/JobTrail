import { randomUUID } from 'node:crypto';
import { validRevision } from './hosted_fixture_plan.mjs';

const origin = 'https://ehzdmsdhdlqmicmwbnwh.supabase.co';
const required = [
  'JOBTRAIL_SUPABASE_PUBLISHABLE_KEY',
  'JOBTRAIL_TEST_A_EMAIL',
  'JOBTRAIL_TEST_A_PASSWORD',
  'JOBTRAIL_TEST_B_EMAIL',
  'JOBTRAIL_TEST_B_PASSWORD',
];

const uuidPattern = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const safeErrorCodes = new Set([
  '42501', 'JT001', 'JT002', 'JT003', 'JT005', 'PGRST202', 'PGRST205',
  'invalid_credentials', 'email_not_confirmed', 'over_request_rate_limit',
]);

class SmokeFailure extends Error {
  constructor(message, outcomeUnknown = false) {
    super(message);
    this.outcomeUnknown = outcomeUnknown;
  }
}

function requireThat(condition, message) {
  if (!condition) throw new SmokeFailure(message);
}

function requireReceipt(condition, message) {
  if (!condition) throw new SmokeFailure(message, true);
}

function credentials(env) {
  const missing = required.filter((name) => !env[name]?.trim());
  requireThat(missing.length === 0, `Missing runtime inputs: ${missing.join(', ')}. No HTTP requests sent.`);
  const [key, emailA, passwordA, emailB, passwordB] = required.map((name) => env[name]);
  requireThat(/^sb_publishable_[A-Za-z0-9_-]+$/.test(key),
    'Use the JobTrail project publishable key. No HTTP requests sent.');
  requireThat(emailA.trim().toLowerCase() !== emailB.trim().toLowerCase(),
    'Supply two distinct disposable account emails. No HTTP requests sent.');
  return { key, emailA: emailA.trim(), passwordA, emailB: emailB.trim(), passwordB };
}

function describe(response) {
  const code = response.data?.code ?? response.data?.error_code;
  return `HTTP ${response.status}${safeErrorCodes.has(code) ? ` (${code})` : ''}`;
}

function ok(response, action) {
  if (!response.ok) {
    throw new SmokeFailure(`${action}: expected success, received ${describe(response)}`,
      uncertain(response));
  }
  return response.data;
}

function uncertain(response) {
  return response.write && (response.status >= 500 || [408, 429].includes(response.status));
}

function denied(response, codes, action) {
  const code = response.data?.code ?? response.data?.error_code;
  if (response.ok || !codes.includes(code)) {
    throw new SmokeFailure(`${action}: expected ${codes.join(' or ')}, received ${describe(response)}`,
      uncertain(response) || (response.write && response.ok));
  }
}

function client(key) {
  async function request(action, path, { method = 'GET', token, body, write = false } = {}) {
    const url = new URL(path, origin);
    requireThat(url.origin === origin, `${action}: target origin rejected`);
    const headers = { apikey: key, Accept: 'application/json' };
    if (token) headers.Authorization = `Bearer ${token}`;
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    try {
      const response = await fetch(url, {
        method, headers, redirect: 'error', signal: AbortSignal.timeout(15000),
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      const text = await response.text();
      let data = null;
      if (text) {
        try {
          data = JSON.parse(text);
        } catch {
          // Response text could contain secrets. Only structured status is reported.
        }
      }
      if (write && response.ok && data === null) {
        throw new SmokeFailure('Write receipt missing. Reconcile before continuing.', true);
      }
      return { ok: response.ok, status: response.status, data, write };
    } catch (error) {
      if (error instanceof SmokeFailure) throw error;
      throw new SmokeFailure(`${action}: ${error.name === 'TimeoutError' ?
        'request timed out' : 'request failed or redirect was rejected'}`, write);
    }
  }

  function rpc(name, args = {}, account) {
    return request(name, `/rest/v1/rpc/jobtrail_${name}`, {
      method: 'POST', token: account?.token, body: args, write: name !== 'load_snapshot',
    });
  }

  function rest(table, select, filters, account, options = {}) {
    const query = new URLSearchParams({ select });
    for (const [field, value] of Object.entries(filters)) query.set(field, `eq.${value}`);
    return request(`${options.method ?? 'GET'} ${table}`,
      `/rest/v1/${table}?${query}`, { ...options, token: account?.token, write: Boolean(options.method) });
  }

  async function signIn(label, email, password) {
    const auth = ok(await request(`Sign in ${label}`, '/auth/v1/token?grant_type=password', {
      method: 'POST', body: { email, password },
    }), `Sign in ${label}`);
    requireThat(uuidPattern.test(auth?.user?.id ?? '') && typeof auth?.access_token === 'string'
      && auth.access_token.length > 0, `Sign in ${label}: missing user identity or access token`);
    const user = ok(await request(`Verify identity ${label}`, '/auth/v1/user', {
      token: auth.access_token,
    }), `Verify identity ${label}`);
    requireThat(user?.id === auth.user.id, `Verify identity ${label}: inconsistent Auth user`);
    return { id: user.id, token: auth.access_token };
  }

  return { rpc, rest, signIn };
}

const recordTypes = {
  agendas: { marker: 'location_or_link', deleteRpc: 'delete_agenda' },
  applications: { marker: 'company', deleteRpc: 'delete_application' },
  documents: { marker: 'title', deleteRpc: 'delete_document' },
};

async function cleanup(api, pending, tag) {
  let failures = 0;
  for (const [table, type] of Object.entries(recordTypes)) {
    for (const { id, account } of pending.filter((record) => record.table === table)) {
      const select = `id,user_id,${type.marker},revision`;
      try {
        const rows = ok(await api.rest(table, select, { id }, account), `Cleanup read ${table}`);
        requireThat(Array.isArray(rows) && rows.length <= 1, 'Unexpected cleanup read shape');
        if (rows.length === 0) continue;
        const [row] = rows;
        requireThat(row.id === id && row.user_id === account.id && row[type.marker] === tag && validRevision(row.revision),
          'Cleanup refused a row without the run marker and expected owner');
        if (table === 'applications') {
          const filter = { application_id: id };
          const agendas = ok(await api.rest('agendas', 'id', filter, account), 'Check remaining agendas');
          const links = ok(await api.rest('application_documents', 'document_id', filter, account), 'Check remaining links');
          const trackedDocs = new Set(pending.filter(record =>
            record.table === 'documents' && record.account.id === account.id).map(record => record.id));
          requireThat(Array.isArray(agendas) && agendas.length === 0 &&
            Array.isArray(links) && links.every(link => trackedDocs.has(link.document_id)),
          'Cleanup refused an application with remaining agendas or untracked links.');
        }
        const args = { p_id: id, p_expected_revision: row.revision };
        const receipt = ok(await api.rpc(type.deleteRpc, args, account), `Cleanup delete ${table}`);
        if (receipt !== id) throw new SmokeFailure('Cleanup receipt invalid. Reconcile before retry.', true);
        const remaining = ok(await api.rest(table, 'id', { id }, account), `Cleanup verify ${table}`);
        requireThat(Array.isArray(remaining) && remaining.length === 0, 'Cleanup verification failed');
      } catch (error) {
        failures++;
        const detail = error instanceof SmokeFailure ? error.message : 'unexpected error';
        console.error(`[FAIL] Cleanup ${table} ${id}: ${detail}`);
        if (error.outcomeUnknown) return failures;
      }
    }
  }
  return failures;
}

async function run(input) {
  const api = client(input.key);
  const a = await api.signIn('A', input.emailA, input.passwordA);
  const b = await api.signIn('B', input.emailB, input.passwordB);
  requireThat(a.id !== b.id, 'Auth: disposable accounts resolved to the same user');
  console.log('[PASS] Auth: both password sign-ins and distinct user identities');

  const tag = `JT hosted smoke ${randomUUID()}`;
  const ids = {
    application: randomUUID(), documentA: randomUUID(), documentB: randomUUID(),
    agenda: randomUUID(), crossLink: randomUUID(),
  };
  console.log(`Run marker: ${tag}`);
  console.log(`Fixture IDs: ${JSON.stringify(ids)}`);
  const pending = [];
  function track(table, id, account) {
    pending.push({ table, id, account });
  }

  async function rows(table, select, filters, account) {
    const data = ok(await api.rest(table, select, filters, account), `Read ${table}`);
    requireThat(Array.isArray(data), `Read ${table}: expected an array`);
    return data;
  }

  async function snapshot(account) {
    const data = ok(await api.rpc('load_snapshot', {}, account), 'Read snapshot');
    requireThat(/^\d{4}-\d{2}-\d{2}$/.test(data?.reference_date ?? '') &&
      Number.isFinite(Date.parse(data?.reference_instant)), 'Snapshot: invalid reference clock');
    for (const field of ['applications', 'agendas', 'history', 'documents', 'application_documents']) {
      requireThat(Array.isArray(data[field]), `Snapshot: invalid ${field} collection`);
    }
    return data;
  }

  async function saveDocument(id, account) {
    track('documents', id, account);
    const saved = ok(await api.rpc('save_document', {
      p_id: id, p_create: true, p_title: tag, p_category: 'cv_resume',
      p_file_name: 'smoke.pdf', p_version: '1', p_notes: '',
    }, account), 'Create test document');
    requireReceipt(saved?.id === id && saved.revision === 1 && saved.replayed === false,
      'Document: unexpected create result');
  }

  const appFilter = { id: ids.application };
  const related = { application_id: ids.application };
  const docFilter = { id: ids.documentA };
  let failure;
  try {
    const initial = await snapshot(a);
    const control = await snapshot(b);
    requireThat(initial.entity_revision_version === 1 && control.entity_revision_version === 1,
      'Entity revision migration is required before smoke writes.');
    const appliedOn = initial.reference_date;
    const draft = {
      p_id: ids.application, p_company: tag, p_position: 'Integration test',
      p_source: 'LinkedIn', p_applied_on: appliedOn, p_status: 'screening',
      p_location: 'Surabaya', p_work_type: 'remote', p_salary_monthly_idr: null,
      p_notes: '', p_document_ids: [ids.documentA],
    };
    await saveDocument(ids.documentA, a);
    await saveDocument(ids.documentB, b);
    track('applications', ids.application, a);
    const created = ok(await api.rpc('create_application', draft, a), 'Create linked application');
    requireReceipt(created?.id === ids.application && created.revision === 1 && created.replayed === false,
      'Create: expected a new application at revision 1');
    const replay = ok(await api.rpc('create_application', draft, a), 'Replay identical create');
    requireReceipt(replay?.id === ids.application && replay.revision === 1 && replay.replayed === true,
      'Replay: expected same ID and revision, marked replayed');

    track('agendas', ids.agenda, a);
    const agenda = ok(await api.rpc('save_agenda', {
      p_id: ids.agenda, p_create: true, p_application_id: ids.application, p_type: 'interview',
      p_scheduled_at: `${appliedOn}T09:00:00+07:00`, p_location_or_link: tag, p_notes: '',
    }, a), 'Create related agenda');
    requireReceipt(agenda?.id === ids.agenda && agenda.revision === 1 && agenda.replayed === false,
      'Agenda: unexpected create result');

    const appRows = await rows('applications', 'id,user_id,company,status,revision', appFilter, a);
    const docRows = await rows('documents', 'id,user_id,title', docFilter, a);
    const agendaRows = await rows('agendas', 'id,user_id,application_id', { id: ids.agenda }, a);
    const links = await rows('application_documents', 'application_id,document_id', related, a);
    const history = await rows('application_status_history', 'status,event_no', related, a);
    requireThat(appRows.length === 1 && appRows[0].user_id === a.id && appRows[0].company === tag &&
      appRows[0].status === 'screening' && appRows[0].revision === 1 &&
      docRows.length === 1 && docRows[0].user_id === a.id && docRows[0].title === tag &&
      agendaRows.length === 1 && agendaRows[0].user_id === a.id && agendaRows[0].application_id === ids.application &&
      links.length === 1 && links[0].document_id === ids.documentA &&
      history.length === 1 && history[0].event_no === 1 && history[0].status === 'screening',
    'Owner REST: incorrect records, link, or initial history');
    const mine = await snapshot(a);
    requireThat(mine.applications.some((row) => row.id === ids.application && row.revision === 1) &&
      mine.documents.some((row) => row.id === ids.documentA && row.revision === 1) &&
      !mine.documents.some((row) => row.id === ids.documentB) &&
      mine.agendas.some((row) => row.id === ids.agenda && row.revision === 1) &&
      mine.application_documents.some((row) => row.application_id === ids.application &&
        row.document_id === ids.documentA) &&
      mine.history.filter((row) => row.application_id === ids.application).length === 1,
    'Owner snapshot: incorrect fixtures or other-account document visible');
    console.log('[PASS] Owner REST/RPC: linked create, exact replay, snapshot, and one initial history event');

    const other = await snapshot(b);
    requireThat(other.documents.some((row) => row.id === ids.documentB) &&
      !other.documents.some((row) => row.id === ids.documentA) &&
      !other.applications.some((row) => row.id === ids.application) &&
      !other.agendas.some((row) => row.id === ids.agenda) &&
      !other.history.some((row) => row.application_id === ids.application) &&
      !other.application_documents.some((row) => row.application_id === ids.application),
    'Cross-account snapshot: incorrect visibility');
    for (const [table, select, filter] of [
      ['applications', 'id', appFilter], ['documents', 'id', docFilter],
      ['agendas', 'id', { id: ids.agenda }],
      ['application_status_history', 'id', related],
      ['application_documents', 'application_id', related],
    ]) {
      requireThat((await rows(table, select, filter, b)).length === 0, `Cross-account read: ${table} leaked a fixture`);
    }
    const revisionOne = { p_id: ids.application, p_expected_revision: 1 };
    denied(await api.rpc('change_status', { ...revisionOne, p_status: 'interview' }, b),
      ['JT001'], 'Cross-account status change');
    denied(await api.rpc('delete_application', revisionOne, b),
      ['JT001'], 'Cross-account application delete');
    track('applications', ids.crossLink, b);
    denied(await api.rpc('create_application', { ...draft, p_id: ids.crossLink }, b),
      ['JT003'], 'Cross-account document link');
    requireThat((await rows('applications', 'id', { id: ids.crossLink }, b)).length === 0 &&
      (await rows('application_status_history', 'id', { application_id: ids.crossLink }, b)).length === 0 &&
      (await rows('application_documents', 'application_id', { application_id: ids.crossLink }, b)).length === 0,
    'Cross-account link: failed create left records behind');
    console.log('[PASS] RLS: two-account reads, cross-account mutations, and link rollback');

    denied(await api.rest('application_status_history', 'id', {}, a, {
      method: 'POST',
      body: { user_id: a.id, application_id: ids.application, status: 'offering',
        changed_at: initial.reference_instant, event_no: 9999 },
    }), ['42501'], 'Direct insert');
    denied(await api.rest('applications', 'id', appFilter, a, {
      method: 'PATCH', body: { company: tag },
    }), ['42501'], 'Direct update');
    denied(await api.rest('applications', 'id', appFilter, a, {
      method: 'DELETE',
    }), ['42501'], 'Direct delete');
    denied(await api.rest('applications', 'id', appFilter), ['42501', 'PGRST205'], 'Anonymous REST read');
    denied(await api.rpc('load_snapshot'), ['42501', 'PGRST202'], 'Anonymous snapshot');
    denied(await api.rpc('delete_application', revisionOne), ['42501', 'PGRST202'], 'Anonymous mutation');
    requireThat((await rows('applications', 'status,revision', appFilter, a))
      .some((row) => row.status === 'screening' && row.revision === 1),
    'Denied writes: owner record changed');
    console.log('[PASS] Access grants: direct INSERT/UPDATE/DELETE and anonymous reads/RPCs denied');

    const edited = ok(await api.rpc('update_application', {
      ...draft, ...revisionOne, p_notes: 'Edited by smoke test',
    }, a), 'Save full edit');
    requireReceipt(edited?.id === ids.application && edited.revision === 2,
      'Full edit: expected revision 2');
    requireThat((await rows('application_status_history', 'id', related, a)).length === 1,
      'Full edit: expected unchanged history');
    const revisionTwo = { p_id: ids.application, p_expected_revision: 2 };
    const changed = ok(await api.rpc('change_status', { ...revisionTwo, p_status: 'interview' }, a), 'Change status');
    requireReceipt(changed?.id === ids.application && changed.revision === 3,
      'Status: expected revision 3');
    denied(await api.rpc('change_status', { ...revisionTwo, p_status: 'rejected' }, a),
      ['JT002'], 'Reject stale revision');
    const after = await rows('application_status_history', 'status,event_no', related, a);
    requireThat(after.length === 2 && after.some((row) => row.event_no === 2 && row.status === 'interview') &&
      (await rows('applications', 'status,revision,notes', appFilter, a)).some((row) =>
        row.status === 'interview' && row.revision === 3 && row.notes === 'Edited by smoke test'),
    'Revision: persisted status, history, or notes are incorrect');
    denied(await api.rpc('delete_document', { p_id: ids.documentA, p_expected_revision: 1 }, a),
      ['JT005'], 'Protect linked document');
    const cascade = await snapshot(a);
    requireThat(cascade.agendas.filter(row => row.application_id === ids.application)
      .every(row => row.id === ids.agenda) &&
      cascade.application_documents.filter(row => row.application_id === ids.application)
        .every(row => row.document_id === ids.documentA),
    'Cascade refused an untracked relationship.');
    const deleted = ok(await api.rpc('delete_application', { p_id: ids.application, p_expected_revision: 3 }, a),
      'Delete application with current revision');
    requireReceipt(deleted === ids.application, 'Application: invalid delete receipt');
    requireThat((await rows('applications', 'id', appFilter, a)).length === 0 &&
      (await rows('agendas', 'id', related, a)).length === 0 &&
      (await rows('application_status_history', 'id', related, a)).length === 0 &&
      (await rows('application_documents', 'application_id', related, a)).length === 0 &&
      (await rows('documents', 'id', docFilter, a)).length === 1,
    'Cascade: child records survived or linked document was deleted');
    console.log('[PASS] Mutations: revisions, stale rejection, linked-document protection, and cascades');
  } catch (error) {
    failure = error;
  } finally {
    if (failure?.outcomeUnknown) {
      console.error('[FAIL] Write outcome unknown. Reconcile the printed fixture IDs before any further writes.');
    } else {
      const cleanupFailures = await cleanup(api, pending, tag);
      if (cleanupFailures) {
        if (!failure) failure = new SmokeFailure('Cleanup incomplete. Review only the printed fixture IDs.');
      } else {
        console.log('[PASS] Cleanup: tracked fixtures absent or removed through owner RPCs');
      }
    }
  }
  if (failure) throw failure;
}

try {
  const args = process.argv.slice(2);
  requireThat(args.length === 0 || (args.length === 1 && args[0] === '--check'),
    'Usage: node supabase/tests/hosted_smoke.mjs [--check]');
  const input = credentials(process.env);
  if (args[0] === '--check') {
    console.log(`[PASS] Runtime inputs present. Target: ${origin}. No HTTP requests sent.`);
  } else {
    await run(input);
    console.log('[PASS] Hosted JobTrail smoke test complete');
  }
} catch (error) {
  console.error(`[FAIL] ${error instanceof SmokeFailure ? error.message : 'Unexpected smoke-test error'}`);
  process.exitCode = 1;
}
