import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { ACCOUNTS, FixtureError, PROFILES, PROJECT, recordSpec, requireThat, uuid } from './hosted_fixture_plan.mjs';
import {
  cleanupRun, createRun, inspectEmpty, verifyRun, withManifest,
} from './hosted_fixture_lifecycle.mjs';

const manifestDirectory = fileURLToPath(new URL('../../.jobtrail-qa/', import.meta.url));
const knownCodes = new Set([
  'invalid_credentials', 'email_not_confirmed', 'over_request_rate_limit',
  '42501', 'JT001', 'JT002', 'JT003', 'JT004', 'JT005', '22023', 'PGRST202',
]);
const permittedMutations = new Set(Object.values(recordSpec)
  .flatMap(({ create, remove }) => [create, remove]));

const USAGE = [
  'node supabase/tests/hosted_fixtures.mjs check',
  'node supabase/tests/hosted_fixtures.mjs verify --profile empty [--hosted-read]',
  'node supabase/tests/hosted_fixtures.mjs create --profile <profile> [--execute]',
  'node supabase/tests/hosted_fixtures.mjs verify --manifest <run-uuid> [--hosted-read]',
  'node supabase/tests/hosted_fixtures.mjs create --manifest <run-uuid> --execute [--settled]',
  'node supabase/tests/hosted_fixtures.mjs cleanup --manifest <run-uuid> [--execute] [--settled]',
].join('\n');

function parseArgs(argv) {
  const [command = 'check', ...args] = argv;
  requireThat(['check', 'create', 'verify', 'cleanup'].includes(command), 'Unknown command.');
  const options = { command };
  const flags = new Map([
    ['--profile', 'profile'], ['--manifest', 'runId'], ['--execute', 'execute'],
    ['--hosted-read', 'read'], ['--settled', 'settled'],
  ]);
  for (let index = 0; index < args.length; index++) {
    const property = flags.get(args[index]);
    requireThat(property && !(property in options), 'Unknown or repeated command option.');
    options[property] = property === 'profile' || property === 'runId' ? args[++index] : true;
    requireThat(options[property] !== undefined, 'Missing command option value.');
  }
  requireThat((!('profile' in options) || PROFILES.includes(options.profile)) &&
    (!('runId' in options) || uuid(options.runId)) &&
    !(options.profile && options.runId), 'Invalid profile or manifest UUID.');
  requireThat(!options.execute || command === 'create' || command === 'cleanup',
    'Write opt-in applies only to create or cleanup.');
  requireThat(!options.read || command === 'verify', 'Read opt-in applies only to verify.');
  requireThat(!options.settled || (options.execute && options.runId), '--settled requires an existing manifest and --execute.');
  requireThat(command !== 'check' || (!options.profile && !options.runId), 'Check does not accept a profile or run.');
  requireThat(command !== 'create' || (options.runId || (options.profile && options.profile !== 'empty')),
    'Create requires a non-empty profile or an existing manifest.');
  requireThat(command !== 'verify' || options.runId || options.profile === 'empty',
    'Verify requires an existing manifest or the empty profile.');
  requireThat(command !== 'cleanup' || options.runId, 'Cleanup requires an existing manifest.');
  return options;
}

export function readConfiguration(env, options) {
  const project = env.JOBTRAIL_SUPABASE_URL ?? PROJECT;
  requireThat(project === PROJECT, 'Project URL must exactly match the approved JobTrail origin.');
  const key = env.JOBTRAIL_SUPABASE_PUBLISHABLE_KEY;
  requireThat(typeof key === 'string' && /^sb_publishable_[A-Za-z0-9_-]+$/.test(key),
    'Set JOBTRAIL_SUPABASE_PUBLISHABLE_KEY to the project publishable key.');
  const email = env.JOBTRAIL_QA_EMAIL?.trim().toLowerCase() ??
    (options.profile === 'empty' || options.command === 'check' ? 'test-a@example.com' : 'test-b@example.com');
  requireThat(ACCOUNTS.has(email), 'Account is not an approved disposable identity.');
  const password = env.JOBTRAIL_QA_PASSWORD;
  requireThat(typeof password === 'string' && password.trim(), 'Set JOBTRAIL_QA_PASSWORD at runtime.');
  return { key, email, password };
}

class RequestFailure extends FixtureError {
  constructor(message, definite = false) {
    super(message);
    this.definite = definite;
  }
}

export async function hostedSession(config, fetchImpl = fetch) {
  async function request(path, { action, token, body, write = false } = {}) {
    const url = new URL(path, PROJECT);
    requireThat(url.origin === PROJECT, 'HTTP target rejected.');
    const headers = { apikey: config.key, Accept: 'application/json' };
    if (token) headers.Authorization = 'Bearer ' + token;
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    let response;
    try {
      response = await fetchImpl(url, {
        method: body === undefined ? 'GET' : 'POST', headers,
        redirect: 'error', signal: AbortSignal.timeout(15_000),
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch {
      throw new RequestFailure(action + ': request failed, timed out, or redirected.' +
        (write ? ' Write outcome unknown.' : ''));
    }
    let data;
    try {
      data = await response.json();
    } catch {
      throw new RequestFailure(action + ': invalid response.' + (write ? ' Write outcome unknown.' : ''));
    }
    if (!response.ok) {
      const code = data?.code ?? data?.error_code;
      const status = response.status;
      const known = knownCodes.has(code);
      const definite = [400, 401, 403, 404, 409, 422].includes(status) && known;
      throw new RequestFailure(action + ': HTTP ' + status + (known ? ' (' + code + ')' : '') +
        (write && !definite ? '. Write outcome unknown.' : '.'), definite);
    }
    return data;
  }
  const auth = await request('/auth/v1/token?grant_type=password', {
    action: 'Password sign-in', body: { email: config.email, password: config.password },
  });
  const token = auth?.access_token;
  requireThat(typeof token === 'string' && token.length > 0 && uuid(auth.user?.id),
    'Password sign-in returned invalid identity.');
  const expectedId = auth.user.id;

  return {
    async identity() {
      const user = await request('/auth/v1/user', { action: 'Identity verification', token });
      requireThat(user?.id === expectedId && typeof user.email === 'string' &&
        user.email.toLowerCase() === config.email,
      'Auth identity does not match the designated account.');
      return { email: config.email, id: expectedId };
    },
    snapshot: () => request('/rest/v1/rpc/jobtrail_load_snapshot', {
      action: 'Snapshot read', token, body: {},
    }),
    async ownerRow(record) {
      requireThat(Object.hasOwn(recordSpec, record.table) && uuid(record.id), 'Fixture ID lookup rejected.');
      const select = record.table === 'applications' ? 'id,user_id,notes,revision' : 'id,user_id,notes';
      const query = new URLSearchParams({ select, id: 'eq.' + record.id });
      const rows = await request('/rest/v1/' + record.table + '?' + query, {
        action: 'Owner row verification', token,
      });
      requireThat(Array.isArray(rows) && rows.length <= 1, 'Owner lookup response invalid.');
      return rows[0];
    },
    mutate(name, args) {
      requireThat(permittedMutations.has(name), 'Fixture mutation RPC rejected.');
      return request('/rest/v1/rpc/jobtrail_' + name, { action: name, token, body: args, write: true });
    },
  };
}

export async function runCli(argv, env, {
  fetchImpl = fetch, directory = manifestDirectory,
  out = console.log, err = console.error,
} = {}) {
  let runId;
  try {
    if (argv.length === 1 && argv[0] === '--help') {
      out(USAGE);
      return 0;
    }
    const options = parseArgs(argv);
    const config = readConfiguration(env, options);
    if (!options.execute && !options.read) {
      if (options.runId) {
        await withManifest(directory, options.runId, manifest => {
          requireThat(manifest, 'Manifest not found.');
          requireThat(manifest.owner.email === config.email, 'Configured email does not match manifest.');
        });
      }
      out('[PASS] Dry-run configuration validated. No hosted requests sent.');
      return 0;
    }

    let report;
    if (options.profile === 'empty') {
      report = await inspectEmpty(await hostedSession(config, fetchImpl));
    } else {
      runId = options.runId ?? randomUUID();
      out('Manifest run UUID: ' + runId);
      report = await withManifest(directory, runId, async (manifest, persist) => {
        requireThat(options.runId ? manifest : !manifest, 'Manifest missing or run UUID already exists.');
        requireThat(!manifest || manifest.owner.email === config.email, 'Configured email does not match manifest.');
        const session = await hostedSession(config, fetchImpl);
        if (options.command === 'verify') return verifyRun(session, manifest, persist);
        if (options.command === 'cleanup') return cleanupRun(session, manifest, persist, options);
        return createRun(session, {
          manifest, runId, profile: options.profile, persist, settled: options.settled,
        });
      });
    }
    out(JSON.stringify(report, null, 2));
    return report.status === 'PASS' ? 0 : report.status === 'PARTIAL CLEANUP' ? 2 : 1;
  } catch (error) {
    err('[FAIL] ' + (error instanceof FixtureError ? error.message : 'Unexpected local or fixture operation failure.'));
    if (runId) err('Review the local manifest before retrying this run.');
    return 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  process.exitCode = await runCli(process.argv.slice(2), process.env);
}
