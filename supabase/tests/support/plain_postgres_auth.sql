-- psql only. Use a fresh, disposable plain PostgreSQL cluster and a database
-- named jobtrail_test_*. This shim is neither a migration nor seed data.
\set ON_ERROR_STOP on
begin;
do $$
begin
    if current_database() !~ '^jobtrail_test_[a-z0-9_]+$'
        or coalesce(inet_server_addr() not in ('127.0.0.1'::inet, '::1'::inet), true)
        or to_regnamespace('auth') is not null then
        raise exception 'Use a fresh jobtrail_test_* database over loopback, without an Auth schema';
    end if;
end
$$;

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid
language sql stable set search_path = ''
as $$
    select coalesce(
        nullif(current_setting('request.jwt.claim.sub', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
    )::uuid;
$$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
commit;
