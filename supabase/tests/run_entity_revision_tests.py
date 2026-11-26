"""Test the forward migration in a fresh, disposable loopback PostgreSQL cluster."""
import argparse
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time


SUPABASE = Path(__file__).resolve().parents[1]
MIGRATIONS = SUPABASE / "migrations"
TESTS = SUPABASE / "tests"
DB = "jobtrail_test_entity_revisions"
OWNER = "71000000-0000-4000-8000-000000000001"
APP = "72000000-0000-4000-8000-000000000001"
DOCUMENT = "73000000-0000-4000-8000-000000000001"
AGENDA = "74000000-0000-4000-8000-000000000001"


def owner_sql(owner):
    return (
        "set role authenticated; "
        f"""set request.jwt.claims = '{{"role":"authenticated","sub":"{owner}"}}'; """
    )


def seed(connection, run):
    for suffix in ("1", "2"):
        owner, app, doc, agenda = (value[:-1] + suffix for value in (OWNER, APP, DOCUMENT, AGENDA))
        run(*connection, "-c", f"""
            insert into auth.users (id) values ('{owner}');
            {owner_sql(owner)}
            select public.jobtrail_save_document('{doc}', true, 'Original CV',
                'cv_resume', 'original.pdf', '1');
            select public.jobtrail_create_application('{app}', 'Fixture', 'Engineer', 'Website',
                '2025-06-15', 'applied', 'Surabaya', 'hybrid', p_document_ids => array['{doc}'::uuid]);
            select public.jobtrail_save_agenda('{agenda}', true, '{app}', 'interview',
                '2025-06-15 00:00:00+07', 'Original room');
        """)


def compete(connection, run, env, resource, mutation, verify):
    """Hold the winner's lock, observe the loser waiting, then commit."""
    def session(name, *args, **options):
        return subprocess.Popen([*connection, *args], env={**env, "PGAPPNAME": name},
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **options)

    def wait_for(condition):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            result = run(*connection, "-c", condition, capture_output=True).stdout.strip()
            if result == "t":
                return
            time.sleep(0.05)
        raise RuntimeError(f"{resource}: could not observe the competing transaction state")

    winner = session("revision_winner", stdin=subprocess.PIPE)
    loser = None
    try:
        winner.stdin.write(f"begin; {owner_sql(OWNER)} {mutation('Winner')};\n")
        winner.stdin.flush()
        wait_for(f"""
            select exists (select 1 from pg_stat_activity
                where application_name = 'revision_winner' and state = 'idle in transaction'
                and query like '%jobtrail_save_{resource}%')
        """)
        loser = session("revision_loser", "-c", f"{owner_sql(OWNER)} {mutation('Loser')}")
        wait_for("""
            select exists (select 1 from pg_stat_activity loser, pg_stat_activity winner
              where loser.application_name = 'revision_loser'
                and winner.application_name = 'revision_winner'
                and winner.pid = any (pg_blocking_pids(loser.pid)))
        """)
        out, err = winner.communicate("commit;\n", timeout=10)
        if winner.returncode or '"revision": 2' not in out:
            raise RuntimeError(f"{resource}: winner failed to commit revision 2: {err}")
        out, err = loser.communicate(timeout=10)
        if loser.returncode != 1 or "JT002" not in err:
            raise RuntimeError(f"{resource}: expected one stale loser: {out} {err}")
        result = run(*connection, "-c", f"{owner_sql(OWNER)} {verify}", capture_output=True)
        if result.stdout.strip() != "t":
            raise RuntimeError(f"{resource}: winner payload or revision was lost")
        print(f"{resource}: two sessions used revision 1, one committed revision 2, one received JT002")
    finally:
        for process in (loser, winner):
            if process is not None and process.poll() is None:
                process.kill()
                process.communicate(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pg-bin", type=Path, required=True, help="Existing PostgreSQL bin directory")
    bin_dir = parser.parse_args().pg_bin.resolve()
    suffix = ".exe" if os.name == "nt" else ""
    initdb, pg_ctl, psql = (str(bin_dir / (name + suffix)) for name in ("initdb", "pg_ctl", "psql"))
    env = {key: value for key, value in os.environ.items() if not key.upper().startswith("PG")}
    env["PGCONNECT_TIMEOUT"] = "5"
    env["PGOPTIONS"] = "-c statement_timeout=20000"

    def run(*args, **options):
        return subprocess.run(args, env=env, text=True, check=True, timeout=45, **options)

    with tempfile.TemporaryDirectory(prefix="jobtrail-entity-revisions-") as directory:
        data = str(Path(directory) / "pgdata")
        log = str(Path(directory) / "postgres.log")
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = str(sock.getsockname()[1])
        run(initdb, "-D", data, "-U", "postgres", "-A", "trust", "--locale=C", "--encoding=UTF8",
            stdout=subprocess.DEVNULL)
        run(pg_ctl, "-D", data, "-l", log, "-o", f"-h 127.0.0.1 -p {port}", "-w", "start")
        try:
            base = [psql, "-X", "-qAtw", "-h", "127.0.0.1", "-p", port, "-U", "postgres",
                    "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"]
            run(*base, "-d", "postgres", "-c", f"create database {DB}")
            connection = [*base, "-d", DB]
            run(*connection, "-f", str(TESTS / "support/plain_postgres_auth.sql"))
            # Reproduce migration ownership requirements without superuser DDL.
            run(*connection, "-c", f"""
                create role jobtrail_migration_owner nologin createrole;
                grant create on database {DB} to jobtrail_migration_owner;
                alter schema public owner to jobtrail_migration_owner;
                grant usage on schema auth to jobtrail_migration_owner;
                grant references on auth.users to jobtrail_migration_owner;
            """)
            as_migrator = [*connection, "-c", "set role jobtrail_migration_owner"]
            for name in ("20261124000100_jobtrail_schema.sql", "20261124000200_jobtrail_access.sql"):
                run(*as_migrator, "-f", str(MIGRATIONS / name))
            seed(connection, run)
            run(*as_migrator, "-f", str(MIGRATIONS / "20261126000100_jobtrail_entity_revisions.sql"))
            run(*connection, "-f", str(TESTS / "entity_revision_contract.sql"))
            compete(connection, run, env, "document", lambda label: (
                f"select public.jobtrail_save_document('{DOCUMENT}', false, '{label}', "
                "'cv_resume', 'original.pdf', '1', p_expected_revision => 1)"
            ), f"select revision = 2 and title = 'Winner' from public.documents where id = '{DOCUMENT}'")
            compete(connection, run, env, "agenda", lambda label: (
                f"select public.jobtrail_save_agenda('{AGENDA}', false, '{APP}', 'test', "
                f"'2025-06-15 00:00:00+07', '{label}', p_expected_revision => 1)"
            ), f"select revision = 2 and location_or_link = 'Winner' from public.agendas where id = '{AGENDA}'")
            run(*connection, "-f", str(TESTS / "database_contract.sql"))
        finally:
            run(pg_ctl, "-D", data, "-m", "fast", "-w", "stop")


if __name__ == "__main__":
    main()
