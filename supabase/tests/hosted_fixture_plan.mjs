import { createHash } from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';

export const PROJECT = 'https://ehzdmsdhdlqmicmwbnwh.supabase.co';
export const ACCOUNTS = new Set([
  'test-a@example.com', 'test-b@example.com', 'hanif@example.com',
  'lenno@example.com', 'rifqi@example.com', 'fachriza@example.com',
  'farhad@example.com', 'ziyaad@example.com',
]);
export const PROFILES = ['empty', 'standard', 'board', 'detail', 'form', 'schedule', 'documents', 'statistics'];
export const COLLECTIONS = ['applications', 'agendas', 'documents', 'history', 'application_documents'];
const statuses = ['applied', 'screening', 'test', 'interview', 'offering', 'rejected'];
const dayMs = 86_400_000;
const wibMs = 7 * 3_600_000;
const uuidPattern = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;

export class FixtureError extends Error {}
export function requireThat(condition, message) {
  if (!condition) throw new FixtureError(message);
}
export function uuid(value) {
  return typeof value === 'string' && uuidPattern.test(value);
}
function date(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    Number.isFinite(Date.parse(value)) && isoDate(Date.parse(value)) === value;
}
function isoDate(ms) {
  return new Date(ms).toISOString().slice(0, 10);
}
function instant(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(value) &&
    date(value.slice(0, 10)) && Number.isFinite(Date.parse(value));
}
export function validateClock(clock) {
  requireThat(date(clock?.reference_date) && instant(clock.reference_instant) &&
    isoDate(Date.parse(clock.reference_instant) + wibMs) === clock.reference_date,
  'Invalid or inconsistent WIB snapshot clock.');
}
export function monday(referenceDate) {
  const ms = Date.parse(referenceDate);
  return ms - ((new Date(ms).getUTCDay() + 6) % 7) * dayMs;
}
function periodStart(today, months) {
  const d = new Date(today);
  const first = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() - months, 1));
  const lastDay = new Date(Date.UTC(first.getUTCFullYear(), first.getUTCMonth() + 1, 0)).getUTCDate();
  first.setUTCDate(Math.min(d.getUTCDate(), lastDay));
  return first.getTime();
}
function fixtureId(run, label) {
  // Domain-separated UUID v8 derived from the random run UUID and a fixed label.
  const bytes = createHash('sha256').update('jobtrail-qa-v1/' + run + '/' + label).digest();
  bytes[6] = (bytes[6] & 0x0f) | 0x80;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.subarray(0, 16).toString('hex');
  return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20),
    hex.slice(20)].join('-');
}
export const recordSpec = {
  documents: { label: 'document', create: 'save_document', remove: 'delete_document' },
  applications: { label: 'application', create: 'create_application', remove: 'delete_application' },
  agendas: { label: 'agenda', create: 'save_agenda', remove: 'delete_agenda' },
};
export const validRevision = value => Number.isInteger(value) && value > 0 && value <= 2147483647;

export function requireEntityRevisionContract(snapshot) {
  requireThat(snapshot.entity_revision_version === 1,
    'Entity revision migration is required before fixture writes. Keep the manifest and verify the target contract.');
}

export function validateSnapshot(snapshot) {
  validateClock(snapshot);
  const versioned = Object.hasOwn(snapshot, 'entity_revision_version');
  if (versioned) requireEntityRevisionContract(snapshot);
  const hasValidEntityRevision = row => (versioned || Object.hasOwn(row, 'revision'))
    ? validRevision(row.revision) : true;
  for (const collection of COLLECTIONS) {
    const rows = snapshot[collection];
    requireThat(Array.isArray(rows) && rows.every(row =>
      row && (collection === 'application_documents'
        ? uuid(row.application_id) && uuid(row.document_id)
        : uuid(row.id))),
    'Invalid snapshot collection.');
    const ids = rows.map(row => collection === 'application_documents'
      ? row.application_id + '/' + row.document_id : row.id);
    requireThat(new Set(ids).size === rows.length, 'Snapshot contains duplicate identifiers.');
  }
  requireThat(snapshot.applications.every(row => date(row.applied_on) && statuses.includes(row.status) &&
    validRevision(row.revision)) &&
    snapshot.agendas.every(row => uuid(row.application_id) && instant(row.scheduled_at) &&
      ['interview', 'test'].includes(row.type) && hasValidEntityRevision(row)) &&
    snapshot.documents.every(hasValidEntityRevision) &&
    snapshot.history.every(row => uuid(row.application_id) && statuses.includes(row.status) &&
      Number.isInteger(row.event_no) && row.event_no > 0),
  'Invalid snapshot rows.');
  return snapshot;
}

export function metrics(snapshot, clock = snapshot) {
  const today = Date.parse(clock.reference_date);
  const week = monday(clock.reference_date);
  const now = Date.parse(clock.reference_instant);
  const upcoming = snapshot.agendas.filter(row => Date.parse(row.scheduled_at) >= now);
  const weeklyAchieved = snapshot.applications.filter(row => {
    const applied = Date.parse(row.applied_on);
    return applied >= week && applied < week + 7 * dayMs;
  }).length;
  const interviewed = new Set(snapshot.history.filter(row => row.status === 'interview')
    .map(row => row.application_id));
  const periods = Object.fromEntries([0, 1, 2, 3].map(months => {
    const start = months ? periodStart(today, months) : -Infinity;
    const apps = snapshot.applications.filter(row => Date.parse(row.applied_on) >= start);
    const withInterview = apps.filter(row => interviewed.has(row.id)).length;
    return [months ? months + 'm' : 'all', {
      total: apps.length,
      status: Object.fromEntries(statuses.map(status => [status, apps.filter(row => row.status === status).length])),
      interviewEventsDenominator: apps.length,
      applicationsWithInterviewHistory: withInterview,
      interviewConversionPct: apps.length ? 100 * withInterview / apps.length : null,
    }];
  }));
  return {
    weekStartWib: isoDate(week), weeklyTarget: 8, weeklyAchieved,
    weeklyProgressPct: Math.min(100, weeklyAchieved * 12.5),
    upcomingInterviews: upcoming.filter(row => row.type === 'interview').length,
    upcomingAgendas: upcoming.length, agendas: snapshot.agendas.length,
    documents: snapshot.documents.length, links: snapshot.application_documents.length,
    history: snapshot.history.length, periods,
  };
}

export function rowPayload(record) {
  const { p_create, p_document_ids, ...args } = record.args;
  return Object.fromEntries(Object.entries(args).map(([key, value]) => [key.slice(2), value]));
}

export function makePlan(runId, profile, clock) {
  requireThat(uuid(runId) && PROFILES.includes(profile) && profile !== 'empty', 'Invalid run or profile.');
  validateClock(clock);
  const today = Date.parse(clock.reference_date);
  const week = monday(clock.reference_date);
  const now = Date.parse(clock.reference_instant);
  const past = week - dayMs;
  const tag = 'JTQA ' + runId;
  const records = [];
  function add(table, label, fields) {
    const id = fixtureId(runId, table + '/' + label);
    const marker = tag + '/' + recordSpec[table].label + '/' + label;
    records.push({ table, label, id, marker, args: { p_id: id, ...fields, p_notes: marker } });
    return id;
  }
  function doc(label, category = 'cv_resume') {
    return add('documents', label, {
      p_create: true, p_title: 'QA ' + label + ' ' + runId, p_category: category,
      p_file_name: 'synthetic-' + label + '.pdf', p_version: '1',
    });
  }
  function app(label, status, applied = today, docs = [], variant = false) {
    return add('applications', label, {
      p_company: 'QA Perusahaan ' + label + ' ' + runId, p_position: 'QA Posisi ' + label,
      p_source: variant ? 'Website perusahaan' : 'LinkedIn',
      p_applied_on: isoDate(applied), p_status: status,
      p_location: variant ? 'Kota Uji B' : 'Kota Uji A',
      p_work_type: variant ? 'on_site' : 'remote',
      p_salary_monthly_idr: variant && profile !== 'form' ? '4500000' : null,
      p_document_ids: docs,
    });
  }
  function agenda(label, parent, type, scheduled) {
    return add('agendas', label, {
      p_create: true, p_application_id: parent, p_type: type,
      p_scheduled_at: new Date(scheduled).toISOString(),
      p_location_or_link: 'QA Ruang ' + label,
    });
  }

  if (profile === 'standard') {
    const cv = doc('dashboard-cv');
    const old = app('prior-week', 'applied', past);
    app('screening', 'screening', week, [], true);
    app('test', 'test', week);
    const interview = app('interview', 'interview');
    const offering = app('offering', 'offering', today, [cv]);
    app('rejected', 'rejected', week);
    agenda('past-interview', old, 'interview', past + 2 * 3_600_000);
    agenda('upcoming-interview', interview, 'interview', now + dayMs);
    agenda('upcoming-test', offering, 'test', now + 2 * dayMs);
  } else if (profile === 'board') {
    app('transition', 'screening', today, [], true);
    app('interview', 'interview');
    app('offering', 'offering', past);
  } else if (profile === 'detail') {
    const cv = doc('detail-cv');
    const linked = app('cascade', 'interview', today, [cv]);
    app('untouched', 'screening', past);
    agenda('linked', linked, 'interview', now + dayMs);
  } else if (profile === 'form') {
    const cv = doc('form-cv');
    app('stable-create', 'applied', today, [cv], true);
  } else if (profile === 'schedule') {
    const before = app('before-midnight', 'interview', today - dayMs);
    const after = app('after-midnight', 'test');
    const midnight = today + dayMs - wibMs;
    agenda('wib-2359', before, 'interview', midnight - 60_000);
    agenda('wib-0001', after, 'test', midnight + 60_000);
    agenda('next-interview', before, 'interview', now + 2 * dayMs);
  } else if (profile === 'documents') {
    const linked = doc('linked-cv');
    doc('editable-portfolio', 'portfolio');
    app('document-owner', 'applied', today, [linked]);
  } else {
    app('current', 'interview');
    for (let months = 1; months <= 3; months++) {
      const start = periodStart(today, months);
      app('at-' + months + 'm', statuses[months], start);
      app('before-' + months + 'm', months === 1 ? 'offering' : 'rejected', start - dayMs);
    }
  }

  const baseline = Object.fromEntries(COLLECTIONS.map(name => [name, []]));
  for (const record of records) {
    baseline[record.table].push(rowPayload(record));
    if (record.table === 'applications') {
      baseline.history.push({ application_id: record.id, status: record.args.p_status, event_no: 1 });
      for (const document_id of record.args.p_document_ids) {
        baseline.application_documents.push({ application_id: record.id, document_id });
      }
    }
  }
  return { records, relationships: baseline.application_documents, expected: metrics(baseline, clock) };
}

export function fixtureSnapshot(snapshot, records) {
  const ids = Object.fromEntries(Object.keys(recordSpec).map(table =>
    [table, new Set(records.filter(record => record.table === table).map(record => record.id))]));
  const touching = snapshot.application_documents.filter(link =>
    ids.applications.has(link.application_id) || ids.documents.has(link.document_id));
  return {
    ...Object.fromEntries(Object.keys(recordSpec).map(table =>
      [table, snapshot[table].filter(row => ids[table].has(row.id))])),
    history: snapshot.history.filter(row => ids.applications.has(row.application_id)),
    application_documents: touching,
  };
}
export function matchPayload(record, row, snapshot) {
  const expected = rowPayload(record);
  if (record.table === 'agendas' && Date.parse(row.scheduled_at) !== Date.parse(expected.scheduled_at)) return false;
  const fieldsMatch = Object.entries(expected).every(([key, value]) =>
    key === 'scheduled_at' || row[key] === value);
  if (!fieldsMatch || record.table !== 'applications') return fieldsMatch;
  const linked = snapshot.application_documents.filter(link => link.application_id === record.id)
    .map(link => link.document_id).sort();
  return isDeepStrictEqual(linked, [...record.args.p_document_ids].sort());
}
