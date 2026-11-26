import { randomUUID } from 'node:crypto';
import { mkdir, open, readFile, rename, unlink } from 'node:fs/promises';
import { join } from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import {
  ACCOUNTS, COLLECTIONS, FixtureError, PROJECT, fixtureSnapshot, makePlan, matchPayload,
  metrics, recordSpec, requireEntityRevisionContract, requireThat, uuid, validateSnapshot,
} from './hosted_fixture_plan.mjs';

const attempts = ['PENDING', 'IN_FLIGHT', 'CONFIRMED', 'REJECTED', 'UNCERTAIN'];
const terminalOrPending = ['PENDING', 'PASS', 'FAIL'];
const cleanupOrder = ['agendas', 'applications', 'documents'];

export function newManifest(runId, profile, owner, snapshot) {
  const clock = { reference_date: snapshot.reference_date, reference_instant: snapshot.reference_instant };
  const plan = makePlan(runId, profile, clock);
  const pending = () => Object.fromEntries(plan.records.map(record => [record.id, 'PENDING']));
  return {
    version: 1, project: PROJECT, runId, profile, owner: { id: owner.id, email: owner.email },
    clock, plan, creation: 'PENDING', verification: 'PENDING', cleanup: 'PENDING',
    creates: pending(), deletes: pending(),
  };
}

export function validateManifest(manifest, runId) {
  requireThat(manifest && manifest.version === 1 && manifest.project === PROJECT &&
    uuid(runId) && manifest.runId === runId && uuid(manifest.owner?.id) &&
    ACCOUNTS.has(manifest.owner?.email), 'Invalid manifest identity or project.');
  const baseline = newManifest(runId, manifest.profile, manifest.owner, manifest.clock);
  const sameKeys = (left, right) => left && isDeepStrictEqual(Object.keys(left).sort(), Object.keys(right).sort());
  requireThat(sameKeys(manifest, baseline) && sameKeys(manifest.owner, baseline.owner) &&
    isDeepStrictEqual(manifest.clock, baseline.clock) && isDeepStrictEqual(manifest.plan, baseline.plan),
  'Manifest plan or schema differs from the generated template.');
  requireThat(['PENDING', 'PARTIAL', 'PASS'].includes(manifest.creation) &&
    terminalOrPending.includes(manifest.verification) &&
    [...terminalOrPending, 'PARTIAL CLEANUP'].includes(manifest.cleanup) &&
    ['creates', 'deletes'].every(key => sameKeys(manifest[key], baseline[key]) &&
      Object.values(manifest[key]).every(value => attempts.includes(value))),
  'Invalid manifest lifecycle state.');
  return manifest;
}

export async function withManifest(directory, runId, operation) {
  requireThat(uuid(runId), 'Invalid run UUID.');
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const path = join(directory, runId + '.json');
  const lockPath = join(directory, runId + '.lock');
  const lock = await open(lockPath, 'wx', 0o600).catch(error => {
    if (error.code === 'EEXIST') throw new FixtureError('Run is locked. See runbook recovery procedure.');
    throw error;
  });
  try {
    let manifest;
    try {
      const content = await readFile(path, 'utf8');
      try {
        manifest = validateManifest(JSON.parse(content), runId);
      } catch (error) {
        if (error instanceof FixtureError) throw error;
        throw new FixtureError('Invalid manifest JSON.');
      }
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    return await operation(manifest, async value => {
      validateManifest(value, runId);
      const tempPath = join(directory, runId + '.' + randomUUID() + '.tmp');
      const temp = await open(tempPath, 'wx', 0o600);
      try {
        try {
          await temp.writeFile(JSON.stringify(value, null, 2) + '\n', 'utf8');
          await temp.sync();
        } finally {
          await temp.close();
        }
        await rename(tempPath, path);
      } finally {
        await unlink(tempPath).catch(error => {
          if (error.code !== 'ENOENT') throw error;
        });
      }
    });
  } finally {
    await lock.close();
    await unlink(lockPath);
  }
}

async function identify(session, manifest) {
  const owner = await session.identity();
  requireThat(uuid(owner?.id) && ACCOUNTS.has(owner.email), 'Authenticated identity rejected.');
  if (manifest) {
    validateManifest(manifest, manifest.runId);
    requireThat(owner.id === manifest.owner.id && owner.email === manifest.owner.email,
      'Authenticated owner does not match manifest.');
  }
  return owner;
}
async function readSnapshot(session) {
  return validateSnapshot(await session.snapshot());
}
function rowFor(snapshot, record) {
  return snapshot[record.table].find(row => row.id === record.id);
}
const unsettled = status => status === 'IN_FLIGHT' || status === 'UNCERTAIN';
function requireSettled(manifest, settled) {
  requireThat(settled || ![...Object.values(manifest.creates), ...Object.values(manifest.deletes)].some(unsettled),
    'Uncertain write. Reconcile before using --settled.');
}
function matchingOwner(row, record, owner) {
  return row?.id === record.id && row.user_id === owner.id && row.notes === record.marker;
}

export async function inspectEmpty(session) {
  await identify(session);
  const snapshot = await readSnapshot(session);
  const counts = Object.fromEntries(COLLECTIONS.map(table => [table, snapshot[table].length]));
  return { status: Object.values(counts).every(count => count === 0) ? 'PASS' : 'FAIL', counts };
}

export function verificationReport(snapshot, manifest) {
  const scoped = fixtureSnapshot(snapshot, manifest.plan.records);
  const missing = [];
  const changed = [];
  for (const record of manifest.plan.records) {
    const row = rowFor(scoped, record);
    if (!row) missing.push(record.label);
    else if (!matchPayload(record, row, snapshot) ||
        (row.revision !== undefined && row.revision !== 1)) changed.push(record.label);
  }
  const baselineComparison = metrics(scoped, manifest.clock);
  const historiesMatch = scoped.history.length === scoped.applications.length &&
    scoped.applications.every(row => scoped.history.some(event =>
      event.application_id === row.id && event.status === row.status && event.event_no === 1));
  const status = !missing.length && !changed.length && historiesMatch &&
    isDeepStrictEqual(baselineComparison, manifest.plan.expected) ? 'PASS' : 'FAIL';
  const unrelated = Object.fromEntries(COLLECTIONS.map(table => [table, snapshot[table].length - scoped[table].length]));
  const applicationChecks = manifest.plan.records.filter(record => record.table === 'applications')
    .flatMap(record => {
      const row = rowFor(scoped, record);
      if (!row) return [];
      const history = scoped.history.filter(event => event.application_id === record.id)
        .sort((a, b) => a.event_no - b.event_no)
        .map(event => ({ event: event.event_no, status: event.status }));
      return [{ label: record.label, status: row.status, revision: row.revision, history }];
    });
  return {
    status, missing, changed, historiesMatch, unrelated, applicationChecks,
    expectedAtPreparation: manifest.plan.expected, actualAtPreparation: baselineComparison,
    referenceDateWib: snapshot.reference_date, referenceInstant: snapshot.reference_instant,
    fixturesNow: metrics(scoped, snapshot), accountNow: metrics(snapshot),
  };
}

export async function verifyRun(session, manifest, persist) {
  await identify(session, manifest);
  const report = verificationReport(await readSnapshot(session), manifest);
  manifest.verification = report.status;
  await persist(manifest);
  return report;
}

export async function createRun(session, { manifest, runId, profile, persist, settled = false }) {
  const owner = await identify(session, manifest);
  const snapshot = await readSnapshot(session);
  requireEntityRevisionContract(snapshot);
  if (!manifest) {
    manifest = newManifest(runId, profile, owner, snapshot);
    await persist(manifest);
  }
  requireThat(manifest.cleanup === 'PENDING', 'A cleanup attempt prevents resuming creation.');
  if (manifest.creation === 'PASS') {
    return verificationReport(snapshot, manifest);
  }
  requireSettled(manifest, settled);
  // Refuse collisions anywhere in the plan before starting additional writes.
  for (const record of manifest.plan.records) {
    const existing = rowFor(snapshot, record);
    if (existing) {
      requireThat((manifest.creates[record.id] === 'CONFIRMED' || unsettled(manifest.creates[record.id])) &&
        matchPayload(record, existing, snapshot) &&
        existing.revision === 1,
      'Create refused an unexpected existing fixture ID.');
      const checked = await session.ownerRow(record);
      requireThat(matchingOwner(checked, record, owner) && checked.revision === existing.revision,
        'Create refused an unexpected existing fixture owner or revision.');
    } else {
      requireThat(manifest.creates[record.id] !== 'CONFIRMED',
        'Previously confirmed fixture is absent. Creation stopped to prevent recreation.');
    }
  }

  manifest.creation = 'PARTIAL';
  for (const record of manifest.plan.records) {
    if (rowFor(snapshot, record)) {
      manifest.creates[record.id] = 'CONFIRMED';
      continue;
    }
    manifest.creates[record.id] = 'IN_FLIGHT';
    await persist(manifest);
    try {
      const receipt = await session.mutate(recordSpec[record.table].create, record.args);
      requireThat(receipt?.id === record.id && typeof receipt.replayed === 'boolean' &&
        receipt.revision === 1,
      'Create receipt inconsistent. Write outcome unknown.');
      manifest.creates[record.id] = 'CONFIRMED';
    } catch (error) {
      manifest.creates[record.id] = error.definite ? 'REJECTED' : 'UNCERTAIN';
      await persist(manifest);
      throw error;
    }
    await persist(manifest);
  }
  const report = verificationReport(await readSnapshot(session), manifest);
  manifest.verification = report.status;
  if (report.status === 'PASS') manifest.creation = 'PASS';
  await persist(manifest);
  return report;
}

function preflight(snapshot, manifest) {
  const fixture = fixtureSnapshot(snapshot, manifest.plan.records);
  const apps = new Set(fixture.applications.map(row => row.id));
  const docs = new Set(fixture.documents.map(row => row.id));
  const agendas = new Set(fixture.agendas.map(row => row.id));
  const appIds = new Set(manifest.plan.records.filter(row => row.table === 'applications').map(row => row.id));
  const docIds = new Set(manifest.plan.records.filter(row => row.table === 'documents').map(row => row.id));
  for (const record of manifest.plan.records) {
    const current = rowFor(fixture, record);
    if (!current) continue;
    requireThat(!['PENDING', 'REJECTED'].includes(manifest.creates[record.id]) &&
      manifest.deletes[record.id] !== 'CONFIRMED' && current.notes === record.marker,
    'Cleanup refused an unexpected record or marker.');
    if (record.table === 'agendas') {
      requireThat(apps.has(current.application_id), 'Cleanup refused a fixture agenda moved outside the run.');
    }
  }
  requireThat(!snapshot.agendas.some(row => appIds.has(row.application_id) && !agendas.has(row.id)),
    'Cleanup refused an unrelated agenda on a fixture application.');
  requireThat(fixture.application_documents.every(link => apps.has(link.application_id) && docs.has(link.document_id)),
    'Cleanup refused a relationship outside the run.');
  return fixture;
}
function remainingCount(snapshot, records) {
  const fixtures = fixtureSnapshot(snapshot, records);
  const parents = new Set(records.filter(record => record.table === 'applications').map(record => record.id));
  const outsideAgendas = snapshot.agendas.filter(row => parents.has(row.application_id) &&
    !fixtures.agendas.some(fixture => fixture.id === row.id)).length;
  return COLLECTIONS.reduce((total, table) => total + fixtures[table].length, outsideAgendas);
}

export async function cleanupRun(session, manifest, persist, { settled = false } = {}) {
  const identity = await identify(session, manifest);
  let snapshot = await readSnapshot(session);
  requireEntityRevisionContract(snapshot);
  let started = Object.values(manifest.deletes).some(status => status !== 'PENDING');
  try {
    requireSettled(manifest, settled);
    const wasClean = manifest.cleanup === 'PASS';
    if (wasClean) {
      requireThat(remainingCount(snapshot, manifest.plan.records) === 0,
        'A previously cleaned fixture or relationship reappeared.');
      return { status: 'PASS', remaining: 0 };
    }
    preflight(snapshot, manifest);
    const revisions = new Map();
    for (const record of manifest.plan.records) {
      const row = rowFor(snapshot, record);
      if (!row) continue;
      const checked = await session.ownerRow(record);
      requireThat(matchingOwner(checked, record, identity) && checked.revision === row.revision,
        'Cleanup refused ownership, marker or revision mismatch.');
      revisions.set(record.id, row.revision);
    }

    for (const table of cleanupOrder) {
      for (const record of manifest.plan.records.filter(record => record.table === table)) {
        snapshot = await readSnapshot(session);
        requireEntityRevisionContract(snapshot);
        preflight(snapshot, manifest);
        const row = rowFor(snapshot, record);
        if (!row) {
          if (unsettled(manifest.creates[record.id])) manifest.creates[record.id] = 'REJECTED';
          if (unsettled(manifest.deletes[record.id])) manifest.deletes[record.id] = 'CONFIRMED';
          continue;
        }
        const checked = await session.ownerRow(record);
        const revision = revisions.get(record.id);
        requireThat(row.revision === revision && matchingOwner(checked, record, identity) &&
          checked.revision === revision,
        'Cleanup refused a changed record between reads.');
        if (unsettled(manifest.creates[record.id])) manifest.creates[record.id] = 'CONFIRMED';
        const args = { p_id: record.id, p_expected_revision: revision };
        manifest.cleanup = 'PARTIAL CLEANUP';
        manifest.deletes[record.id] = 'IN_FLIGHT';
        await persist(manifest);
        started = true;
        try {
          const receipt = await session.mutate(recordSpec[table].remove, args);
          requireThat(receipt === record.id, 'Delete receipt inconsistent. Write outcome unknown.');
          manifest.deletes[record.id] = 'CONFIRMED';
        } catch (error) {
          manifest.deletes[record.id] = error.definite ? 'REJECTED' : 'UNCERTAIN';
          throw error;
        }
        await persist(manifest);
      }
    }
    const remaining = remainingCount(await readSnapshot(session), manifest.plan.records);
    manifest.cleanup = remaining === 0 ? 'PASS' : 'PARTIAL CLEANUP';
    await persist(manifest);
    return { status: manifest.cleanup, remaining };
  } catch (error) {
    manifest.cleanup = started || Object.values(manifest.creates).some(unsettled) ? 'PARTIAL CLEANUP' : 'FAIL';
    await persist(manifest);
    return {
      status: manifest.cleanup,
      reason: error instanceof FixtureError ? error.message : 'Unexpected cleanup failure.',
    };
  }
}
