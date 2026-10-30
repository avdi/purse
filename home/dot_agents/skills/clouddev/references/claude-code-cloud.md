# Claude Code cloud — measured behavior

Everything here was **measured on 2026-10-30** against an Anthropic-hosted
environment (Mailstrom: Rails, Postgres, two Redis, CouchDB, Vault, mailhog,
~2 GB of service images plus a multi-GB dev image). Platform facts decay:
re-measure with `probe-prepare.sh` before relying on a number for a decision
that costs real time. The docs (<https://code.claude.com/docs/en/cloud-environments>)
state intent; this file records what the box did.

The box: 4 CPU, 15 GiB RAM, 252 GB disk with ~30 GB free, Firecracker kernel
`6.18.44-fc`, root with working `sudo`, Ruby 3.3.6, Node 22, no `direnv`.
Docker 29.9.2 and Compose v5.6.1 are installed. **No Docker daemon is
running.** Storage driver `overlayfs` (the containerd image store), cgroup v1.

## Choosing and driving an environment

- **Pick the environment in the claude.ai/code web UI**: repo, then the
  environment picker, then the branch picker. `claude --cloud "<prompt>"`
  starts a session, but `--environment` accepts only self-hosted ids
  (`ccpool_…`); an Anthropic-hosted environment's *name* is rejected.
- The branch picked for the session is the branch whose `script/…` the setup
  script runs. Provisioning code can be iterated on a branch.
- The session agent has no `get_environment` / `update_environment` tools. It
  cannot read or change the setup script, so it cannot fix a failed setup; a
  human edits the environment.
- The session agent can read files the setup script left on disk. That is the
  channel for setup diagnostics (see *Setup output*).

## The setup script

**Working directory.** The script starts in `/home/user`; the checkout is
`/home/user/<repo>` (here `/home/user/mailstrom`). Write the environment's
script as

```bash
#!/usr/bin/env bash
cd /home/user/mailstrom && script/clouddev/prepare
```

A relative `script/clouddev/prepare` fails with exit 127 ("No such file or
directory") because the working directory is not the repo.

**Setup output.** The platform shows the script's output only when it exits
non-zero. A clean exit hides everything. Write a report to a file
(`tee /var/lib/<probe>/report.txt`); the session agent can `cat` it.
A failed setup still starts a session, with the failure text on top.

**Snapshot.** Exit 0 snapshots the disk. Exit non-zero leaves no snapshot: the
next session starts from a clean disk and pays for setup again.

| Survives into the next session | Does not survive |
|---|---|
| Files, including `/var/lib/docker` (2.2 GB of service images measured) | Running processes — `dockerd` and every container are gone |
| Stamp files written by setup | User-defined environment variables, as seen *by setup* |

A restored session reaches "started Claude Code" in seconds. A cold setup that
pulled six service images took about 1:30.

**Invalidation.** The snapshot is keyed on the environment configuration, not
the repo:

- A new commit on the branch does **not** re-run setup. `prepare` is frozen
  in the snapshot; changing `script/clouddev/prepare` in the repo has no
  effect until the environment rebuilds.
- Editing the setup script's text in the UI re-runs it. A one-character
  comment (`# 13`) is enough.
- The docs say a changed allowed-host list also re-runs it, and that the cache
  expires after about seven days. Not measured.

So `boot` (the `SessionStart` hook, which runs every session) tops up what a
frozen snapshot misses: start `dockerd` and the services, then run the cheap
`bundle install` / `yarn install` / migration checks against the checked-out
lockfiles.

**Environment variables.**

| Variable kind | Visible in setup | Visible in the session |
|---|---|---|
| User-defined (`MY_TEST_SECRET`, added in the environment UI) | **no** (measured three times) | yes |
| Platform (`CCR_*`, `SSL_CERT_FILE`, `NODE_EXTRA_CA_CERTS`, `REQUESTS_CA_BUNDLE`, `CLAUDE_CODE_PROXY_RESOLVES_HOSTS`, `NODE_OPTIONS`) | yes | yes |

Consequences:

- A switch the setup script needs (`--no-build`) goes in the script text as an
  **argument**; an env var never arrives.
- A registry token cannot be used in setup. Publish the dev image publicly
  (no token), or pull it from `boot`.
- `CLOUDDEV_TOPOLOGY` is read by `boot`/`exec` in the session, where user
  variables are visible. `prepare` must not read it.

## Docker

- **Start the daemon yourself.** The script runs `dockerd >/tmp/dockerd.log 2>&1 &`
  and waits up to ~30 s for `docker info` to succeed. It starts cleanly as
  root. Print the log tail if it does not.
- A public image pulled in 1 s. Six backing services (postgres 14.2,
  2× redis 8.2, couchdb 3.4.2, vault 1.14.10, mailhog) pulled in 19 s and were
  all healthy 21 s after `docker compose up -d --wait`. About 2.3 GB of images;
  ~14 GB of disk used afterwards.
- Backing services published no ports. Reach them by compose service name from
  another container, or add a port-publishing override for direct topology.

## Network and TLS

**Allowlist mode blocks by DNS.** A host outside the allowlist fails with
`Could not resolve host` (curl exit 6, HTTP status `000`), not with an HTTP
error. apt then reports `Err:… Could not resolve` and the first `install`
fails with `has no installation candidate`. **Full network access** avoids
building a long allowlist (a Rails dev image touches about twenty hosts:
`deb.debian.org`, `security.debian.org`, `apt.postgresql.org`,
`www.postgresql.org`, `registry.npmjs.org`, `rubygems.org`,
`packages.stripe.dev`, `dl.google.com`, `astral.sh`, `sentry.io`,
`s3.amazonaws.com`, `raw.githubusercontent.com`, `cdn.playwright.dev`, …).

**The egress gateway intercepts TLS.** HTTPS is re-signed by
`/O=Anthropic/CN=sandbox-egress-gateway-production Egress Gateway CA`.

- The box trusts it: four files under `/usr/local/share/ca-certificates/`
  (`egress-gateway-ca-production.crt`, `swp-ca-production.crt`, and `-staging`
  twins), merged into `/etc/ssl/certs/ca-certificates.crt` (121 certs), plus
  `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `NODE_EXTRA_CA_CERTS`.
- **Containers do not trust it.** Inside `docker build` and `docker run`,
  every HTTPS call fails: `gem update --system` reports
  `Root certificate is not trusted (… Egress Gateway CA)`. apt works only
  because Debian mirrors use `http://`.

**Runtime fix (verified, HTTP 200).** Mount the host bundle into the container
at a path of your choosing and point the client at it:

```bash
docker run --rm \
  -v /etc/ssl/certs/ca-certificates.crt:/host-ca.pem:ro \
  -e CURL_CA_BUNDLE=/host-ca.pem \
  curlimages/curl -sS -o /dev/null -w '%{http_code}\n' https://rubygems.org/
```

Mounting at `/etc/ssl/certs/` is not enough: `curlimages/curl` sets
`CURL_CA_BUNDLE=/cacert.pem`. For the app container set all of
`CURL_CA_BUNDLE`, `SSL_CERT_FILE`, `NODE_EXTRA_CA_CERTS` (Node ignores the
system store) and `REQUESTS_CA_BUNDLE`, from a compose override that only the
cloud adapter loads.

**Build-time fix (unsolved; do not retry the re-tag).** The Dockerfile's
`FROM ruby:…` / `FROM node:…` resolve in BuildKit against the registry's
digest (`docker.io/library/ruby:3.3.12-bookworm@sha256:<registry digest>`),
ignoring a local image re-tagged with the gateway CA added. The log shows
`load metadata for docker.io/library/ruby:…`. Probable causes: the
`# syntax=docker/dockerfile:1` frontend plus the containerd image store; not
confirmed. `gem update --system` then fails exactly as before. Building the
dev image inside setup also leaves ten more HTTPS steps to fix (npm ×3, `uv`,
Sentry CLI, Playwright download, …). **Build the image in CI, publish it, and
`docker pull` it in `prepare`.**

## Repository traps

- **Gitignored files a fresh clone lacks.** `compose.services.yml` names
  `env_file: app.local.env`, which is gitignored; compose fails with
  `env file … not found`. The devcontainer's host-side step,
  `.devcontainer/sidecar/initialize`, creates the env files, the secrets
  directory, `postgres_password` and the generated override files. It runs
  unchanged on the cloud box (warnings only: no GitHub token, no SSH keys).
  Call it in `prepare` before `compose up`.
- `direnv` is absent. A script that loads `direnv` must treat that as normal.
- Ruby 3.3.6 and Node 22 on the box differ from a project's pinned versions;
  use the container's toolchain, not the box's.

## Probe method

`probe-prepare.sh` (same directory) is the instrument that produced the facts
above. Copy it to `script/clouddev/prepare`, adjust the three path constants,
and use this procedure.

1. **Report to disk.** The script `tee`s everything into
   `/var/lib/clouddev-probe/report.txt`, and appends a line to
   `/var/lib/clouddev-probe/runs` each time it runs. It writes the full build
   log to `build.log` (`docker compose build --progress=plain`).
2. **Exit 1 only for the failure you want shown.** Exit 0 snapshots; exit 1
   shows stdout. A `--no-build` argument returns 0 after the services are
   healthy, giving the cache test a clean run without depending on the build.
3. **Read the files through the session agent**, with fixed commands so the
   output is uncut:

   ```
   head -40 /var/lib/clouddev-probe/report.txt
   grep -nE '^#[0-9]+ [0-9.]+ ' /var/lib/clouddev-probe/build.log | tail -45
   cat /var/lib/clouddev-probe/runs
   ```

4. **Caching test: two sessions, no change between them.** Setup must exit 0
   once. In a *new* session (not a resumed one), run `date -u; uptime -s;
   pgrep -a dockerd; cat …/runs; du -sh /var/lib/docker; head -6 …/report.txt`.

   | Observation | Meaning |
   |---|---|
   | `uptime -s` later than the stamp, no `dockerd`, `runs` still one line, report header unchanged | Snapshot restored; setup did not re-run |
   | `runs` has two lines; report lists the earlier run | Setup re-ran on a restored disk |
   | one new line, report says "none", no `/var/lib/docker` | No caching; every session starts clean |
   | `dockerd` and containers still running | Same VM; nothing was tested |

5. **Do not touch the repo between the two sessions.** A commit does not
   invalidate the cache, but it muddies what a later read means. Force a
   rebuild only by editing the setup script's text.
6. **Read the log, not the platform's summary.** The truncated setup output
   hides the failing line. Use `--progress=plain` and grep the `#N <seconds>`
   lines.

## Anti-patterns learned

- Reading "Docker preinstalled" as "Docker running". The client and `dockerd`
  binary exist; start the daemon.
- Passing a setup switch by environment variable. Setup does not see user
  variables.
- Building a multi-GB dev image inside setup behind the TLS-intercepting
  gateway (see *Network and TLS*).
- Calling `script/clouddev/prepare` by a relative path. The working directory
  is `/home/user`.
- Changing the repo between the two cache-test sessions.
- Piping build output through `head`/`tail` in the report and then guessing.
  The apt failure showed only after `--progress=plain` and a grep of the log.
- Accepting a cloud-session agent's unverified guess. It proposed `gnupg` was
  missing; the log showed a DNS failure, then a TLS failure. It cannot read the
  environment and had not read `build.log`.
- Exiting 1 on a path where the snapshot matters. A failed setup leaves no
  snapshot to test.

## What is still unmeasured

- The hard time limit on setup (docs say keep it near five minutes; a 1:30
  setup passed).
- Whether a changed allowed-host list or the seven-day expiry rebuilds the
  environment.
- A real `bundle install` / `yarn install` inside the app container behind
  the gateway, with the CA mounted.
- Pulling a published dev image from ghcr in setup, and its time and disk cost.
