# medusa-platform

Terraform for every environment of [`medusa-app`](https://github.com/ProTechCloud/medusa-app):
a Cloudflare Tunnel, a small GCE instance behind it, and the keyless identities CI uses.

## Layout

```
terraform/
  live/
    org/gcp/_setup            projects, state bucket, identity pool, hubs, developer roles
    org/cloudflare/_setup     zone-wide security settings
    org/cloudflare            DNS that belongs to no environment
    org/posthog               the PostHog project
    org/organization-member-access/…  who may use GCP and PostHog, from one list
    stg/gcp/_setup            stg state bucket, secrets key, spokes, deny policies
    stg/gcp                   the stg infrastructure
    stg/cloudflare            stg tunnel and DNS
    prd/…                     the same: prd/gcp/_setup is applied by setup-cd, the rest planned but never applied
  modules/
    gcp/…  cloudflare/…       shared code, no state of its own
```

One root per scope and provider, one state each. No workspaces, no Terragrunt.

In every root, `main.tf` holds only the wiring: the root-wide locals. A read of another
root's outputs stays in `remote_state.tf`. Every other block sits in a sibling file named for
it, and a root with no wiring has no `main.tf`.

## How CI reaches a cloud

```
GitHub OIDC ──▶ identity pool ──▶ HUB ──tokenCreator──▶ SPOKE ──▶ the project
                                   │                      │
                       no permissions at all      every permission, and
                       beyond becoming one        only inside its own project
                       named spoke
```

The hub is the entry point and holds nothing. An environment's apply spoke may also set who becomes
that environment's deploy and tunnel-token hubs, and its plan spoke may read them. The spoke lives inside the environment it
changes and trusts exactly one hub, set authoritatively — a second path to it cannot be
added without showing as a diff here.

Two identities take the pool straight to a service account, with no hub or spoke, on purpose.
The setup plan reads all three projects, so there is no one environment for a spoke to live
in; it holds only reads. The bootstrap admin is the identity that creates the hubs and spokes,
so it cannot sit behind them; only `_setup-apply.yml` reaches it, in an environment with a
required reviewer.

Three places must be told to make the second hop, because they authenticate separately:
the `google` provider, the `gcs` backend at `init`, and each `terraform_remote_state`.

**A root that manages nothing in Google gets no service account.** The Cloudflare and
PostHog roots need Google only to open their state, so `org/gcp/_setup` binds the GitHub
identity itself — a `principalSet` on the trust rule below — to that root's state prefix in
the management bucket, and to the bucket's key:

```
GitHub OIDC ──▶ identity pool ──▶ the management bucket, under this stack's prefix only
```

There is no hub, no spoke and no impersonation, which is what Google recommends where the
resource accepts a federated principal. The credential is the federated token itself, and it
lives five minutes, because it derives from GitHub's OIDC token: a plan or apply of these
roots has to finish in that window, which today takes seconds.

### What each trust rule requires

A `principalSet` matches one attribute, but the standard needs several claims to hold at
once. The pool therefore builds composite attributes, and the bindings demand an exact
match of the whole string — there is no wildcard anywhere.

| Identity | Must all be true |
|---|---|
| plan hub | this repo · the shared plan workflow · a PR or `dev` |
| apply hub | this repo · the shared apply workflow · the matching environment · `refs/heads/dev` |
| backend deploy hub | the app repo · `backend-cd.yml` · `backend-stg` environment · `refs/heads/stg` |
| setup plan | this repo · `_setup-plan.yml` · a PR or `dev` |
| bootstrap admin | this repo · `_setup-apply.yml` · `setup` or `organization-member-access` environment · `refs/heads/dev` |
| member access PostHog state | this repo · `_posthog-live-apply.yml` · `organization-member-access` environment · `refs/heads/dev` |
| Cloudflare / PostHog state, plan | this repo · that provider's plan workflow · a PR or `dev` |
| Cloudflare / PostHog state, apply | this repo · that provider's apply workflow · `stg`, `prd`, `cloudflare-org` or `posthog-org` · `refs/heads/dev` |

The backend deploy hub and the tunnel-token hubs keep their rules in the environment's
workload root, in `trust.tf`, so renaming a deploy workflow is one ordinary apply there. The
other rules stay in `org/gcp/_setup`.

The claim used is **`job_workflow_ref`**, not `workflow_ref`. The latter names the *caller*,
which any pull request may add; pinning it would pin nothing.

## Bootstrap

Everything below is done once, by a person, for the first apply of an organization. After
that, every `_setup` change goes through `setup-cd` except `org/cloudflare/_setup`, which
stays by hand because it needs the Cloudflare bootstrap token. The hand path also stays for
emergencies.

### 1. The bootstrap admin

Create a dedicated identity used for `_setup` roots and nothing else, so that "who applied
the foundation" is answerable and separable from day-to-day access. It is a service
account, not a person — `medusa-bootstrap@<management project>` — and you become it by
minting a token, never by logging in as it.

Two credentials are needed, because the `_setup` roots reach two clouds: the state lives
in Google, and `org/cloudflare/_setup` creates resources in Cloudflare. Both are set up by
`.envrc.local`, copied from the committed example:

```sh
cp .envrc.local.example .envrc.local && chmod 600 .envrc.local   # then paste the bootstrap token
source .envrc.local                    # in every new terminal
```

It mints the Google token, checks both credentials against the APIs, and refuses to
continue if either is wrong. An environment variable lives only in the window that created
it, and the Google token lasts an hour — so `source` again rather than wondering why a
plan started failing.

The Cloudflare half is an **account** token with `Account API Tokens Write` and nothing
else, created under **Manage Account → API Tokens** — not under My Profile, which makes
user tokens that belong to a person. It is the one Cloudflare credential never stored in
GitHub.

Narrow surface, not low privilege: a token that can mint can mint one with any permission
the account holds. Rotating it is the lever to pull if anything leaks.

At organization scope the Google identity needs `resourcemanager.projectCreator`,
`resourcemanager.projectIamAdmin`, `iam.denyAdmin` and `orgpolicy.policyAdmin`;
`billing.user` on the billing account; and `owner` on the management project.

`orgpolicy.policyAdmin` is the one people forget. Without it the apply fails
only when it reaches the CMEK constraint, several minutes in, with a permission
error that names the policy rather than the identity.

### 2. The management project and the developer group

Both created by hand, both for the same reason: something has to exist before the code
that creates everything else can store its own state.

```sh
gcloud projects create protech-medusa-mgmt --organization=<ORG_ID>
gcloud billing projects link protech-medusa-mgmt --billing-account=<BILLING_ACCOUNT>
```

Then create the group at [groups.google.com](https://groups.google.com), **invite-only**,
and put the developers in it. Google exposes no API for creating consumer groups, and this
organization has no directory for the Cloud Identity API to write into. Membership is
managed in the group from then on, so adding or removing a developer is not a code change.

> If the group does not exist when `org/gcp/_setup` is first applied, the apply fails with
> a "member not found" error that reads like a bug in the code.

### 3. Apply the `_setup` roots, in this order

Order matters: each reads the previous one's outputs through remote state.

```sh
# Every cd below is from the repository root: 3a leaves the shell inside a
# root, so a relative path in 3b would miss.
repo="$(git rev-parse --show-toplevel)"

# Every step below is chained with &&, so the first failure stops everything
# after it. Not `set -e`: in a terminal it closes the window on the first
# error, and inside `( … ) || break` the shell switches it off entirely,
# because the subshell's status is already being tested. 3b sits inside the
# `if` around 3a, so it runs only when the whole of 3a succeeded — including
# the final migration, which runs after `bucket` is already set.
#
# terraform.tfvars is copied from the example only when it does not exist yet,
# so running a step again keeps the values already filled in.

# 3a. org/gcp/_setup — it creates the bucket its own state will live in, so
#     the first apply has to run without a backend at all. `init -backend=false`
#     does not do that: it skips backend *initialisation* and then refuses to
#     apply. The declaration has to be out of the way.
#
#     The bucket name is read before backend.tf goes back: once it is back,
#     every command but init refuses to run. If this stops part way, check
#     whether backend.tf is still named backend.tf.off before running it again.
#
# 3b. the rest. Each needs its own terraform.tfvars first — org/cloudflare
#     wants zone_id, the environment roots want project_id,
#     management_project_id and management_state_bucket. A subshell per root,
#     so each one starts from the repository root again.
if cd "$repo/terraform/live/org/gcp/_setup" &&
  { [ -e terraform.tfvars ] || cp terraform.tfvars.example terraform.tfvars; } &&
  $EDITOR terraform.tfvars &&
  mv backend.tf backend.tf.off &&
  terraform init && terraform apply -input=false &&
  bucket="$(terraform output -raw management_state_bucket)" &&
  mv backend.tf.off backend.tf &&
  terraform init -migrate-state -backend-config="bucket=$bucket"
then
  for root in org/cloudflare/_setup stg/gcp/_setup prd/gcp/_setup; do
    (
      cd "$repo/terraform/live/$root" &&
        { [ -e terraform.tfvars ] || cp terraform.tfvars.example terraform.tfvars; } &&
        $EDITOR terraform.tfvars &&
        terraform init -backend-config="bucket=$bucket" &&
        terraform apply -input=false
    ) || break
  done
fi
```

> Run `source .envrc.local` first, in this terminal. Three things about it are easy to get
> wrong and all three fail in ways that point somewhere else:
>
> - **Do not use `gcloud auth application-default login`** as the bootstrap admin, and do
>   not set `auth/impersonate_service_account` globally. Either makes gcloud chain two
>   hops — you, then that account, then the bootstrap admin — and the second hop is
>   refused.
> - **The `--scopes` are not optional**, even though gcloud warns it ignores them for an
>   impersonated account. Without them the token authenticates but carries no identity,
>   `userinfo` comes back empty, and the project pin stops the run with a message about
>   the credential it could not read.
> - **Never fold stderr into the captured token.** gcloud prints two warnings on every
>   impersonated call, so `$(gcloud ... 2>&1)` puts `WARNING: This command is using
>   service account impersonation` in the variable instead of the token. The result is a
>   401 that names nothing.

### 4. Map the outputs to GitHub variables

CI reads these as repository **variables**, not secrets — none of them is confidential, and
keeping them visible makes a wrong value obvious in a log instead of invisible.

| Variable | Where it comes from |
|---|---|
| `MANAGEMENT_STATE_BUCKET` | `org/gcp/_setup` → `management_state_bucket` |
| `GCP_WIF_AUDIENCE` | `org/gcp/_setup` → `audience` |
| `GCP_PLAN_PROVIDER` / `GCP_APPLY_PROVIDER` | `plan_provider` / `apply_provider` |
| `GCP_PROJECT_STG` / `_PRD` | `environment_projects` |
| `GCP_PLAN_HUB_STG` / `_PRD` | `plan_hubs` |
| `GCP_APPLY_HUB_STG` / `_PRD` | `apply_hubs` |
| `STATE_BUCKET_STG` / `_PRD` | `<env>/gcp/_setup` → `state_bucket` |
| `GCP_PLAN_SPOKE_STG` / `_PRD` | `<env>/gcp/_setup` → `plan_spoke` |
| `GCP_APPLY_SPOKE_STG` / `_PRD` | `<env>/gcp/_setup` → `apply_spoke` |
| `GCP_TUNNEL_TOKEN_WRITER_STG` | `stg/gcp/_setup` → `tunnel_token_writer` |
| `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_ZONE_ID`, `CLOUDFLARE_DOMAIN` | Cloudflare dashboard |
| `POSTHOG_ORGANIZATION_ID` | PostHog → Settings → Organization → General |
| `GCP_SETUP_PLAN` | `org/gcp/_setup` → `setup_plan` |
| `GCP_BOOTSTRAP_ADMIN` | `org/gcp/_setup` → `bootstrap_admin` |
| `PLAN_STORE_BUCKET` | `org/gcp/_setup` → `plan_store_bucket` |
| `GCP_ORG_ID`, `GCP_BILLING_ACCOUNT`, `GCP_MANAGEMENT_PROJECT` | `org_id`, `billing_account`, `management_project_id` in `org/gcp/_setup/terraform.tfvars` |
| `GCP_DEVELOPER_GROUP`, `GCP_ADMINISTRATOR` | `developer_group`, `administrator` in the same file |
| `BACKEND_REPOSITORY` | `backend_repository` in the same file |
| `LIFT_DOMAIN_RULE` | `true` only if the organization sets `iam.allowedPolicyMemberDomains`. Unset otherwise |

Six secrets: two Cloudflare and two PostHog, because neither API has workload identity
federation, and two for the member list. The Cloudflare plan token comes from `org/cloudflare/_setup` and is copied in
once with `terraform output -raw`; the mint token is made by hand, for the reason below.
The PostHog keys are made by hand too: see step 6.

| Secret | Scope | Where its value comes from |
|---|---|---|
| `CLOUDFLARE_MINT_TOKEN` | **environment** secret on `stg`, `prd`, `cloudflare-org` | Made by hand in the Cloudflare dashboard, from the Create Additional Tokens template under Manage Account → API Tokens. Creates and revokes the per-job write tokens. Never a repository secret: `uses: ./…` resolves from the pull request's branch, so a repository secret is reachable by any workflow an unreviewed pull request can rewrite. |
| `CLOUDFLARE_PLAN_TOKEN` | repository secret | `org/cloudflare/_setup` → `plan_token`. Read-only, so a leak buys nothing but reading records that are already public. |
| `POSTHOG_PLAN_API_KEY` | repository secret | A personal API key, read scopes only. Reachable from pull-request code, so its scopes are the whole defence. |
| `POSTHOG_APPLY_API_KEY` | **environment** secret on `posthog-org` and `organization-member-access` | A personal API key that can also write projects and memberships. Environment-only for the same reason as the mint token. |
| `ORG_MEMBERS_ACCESS` | **environment** secret on `organization-member-access` | The member list. See Human access. |
| `POSTHOG_OWNER_EMAIL` | **environment** secret on `organization-member-access` | The PostHog organization's owner, whose level this repository never changes. |

**Every Cloudflare token here is account-owned, not user-owned.** They belong to the
Cloudflare account rather than to a person, so nobody leaving the team takes CI with them,
and that is what Cloudflare documents for automation. In Terraform the resource is
`cloudflare_account_token`; in the workflows the endpoint is `/accounts/{id}/tokens`.

The mint token is the exception, and the one Cloudflare permission here that code cannot
express. Creating it is refused on both APIs:

```
POST /client/v4/user/tokens                  → 400, code 1001   (caller: user token, API Tokens Write)
POST /client/v4/accounts/{account_id}/tokens → 400, code 1001   (caller: account token, Account API Tokens Write)
{"message":"sub-token is not allowed to have permissions to manage other tokens"}
```

Both callers were created in the dashboard, not by another token, so "sub-token" means the
token being created: a token minted through the API may not hold token-management
permission. Cloudflare documents no such rule — this is two observations here and one
matching report elsewhere, and a narrower resource scope has not been tried. If a working
shape turns up, the mint token belongs in `org/cloudflare/_setup` beside the plan token.

Keep the mint token separate from the bootstrap token even though the policy is identical.
One lives in CI and one lives with a person, so they are rotated for different reasons.

A third token exists and is never stored in GitHub: the **bootstrap token** that applies
`org/cloudflare/_setup`. It is an **account** token with `Account API Tokens Write`,
scoped to the account, and no other permission — the same policy as the mint token — and
it lives with the person who applies that root. Narrow surface, not low privilege: Cloudflare's own documentation
says such a token "can create tokens with access to any of a user's resources", so
rotating it is the lever to pull if anything leaks.

GitHub **environments** `stg`, `prd`, `cloudflare-org`, `posthog-org`, `setup` and
`organization-member-access` must exist; their names are part of the trust rules, not labels.
Each accepts deployments from `dev` only. `setup` and `organization-member-access` also need a
required reviewer. The applies in them no longer check that the environment bars self-review or
administrator bypass, so a reviewer may approve a run they started.

### 5. Fill in the secret values

Terraform creates every secret with `REPLACE_ME_VIA_SECRET_MANAGER` and then ignores the
value forever. Set the real ones by hand:

```sh
gcloud secrets versions add medusa_stg_<domain>_<name> \
  --project=medusa-stg --data-file=-
# paste the value, then press ctrl-D
```

Typing the value into the command itself — `printf '%s' '<value>' | …` — writes it
to the shell history, where it outlives the terminal and is readable by anything
that can read the bootstrap account's home directory. `--data-file=-` with no
pipe reads from the terminal instead.

Two are the exception: `stg-cd` writes the tunnel token after each apply, and `org-cd`
writes the PostHog project token to `medusa_stg_posthog_posthog-project-token` after each
PostHog apply.

### 6. PostHog

PostHog has no API to create an organization, invite a person or create a key, so five
things happen once, by hand — the first four before `org/posthog` can run:

1. **Sign up** at [PostHog Cloud US](https://us.posthog.com/signup) and name the
   organization `medusa`. Leave the project sign-up creates: `org/posthog` imports it and
   renames it, so its project token — the one SDKs send with — never changes.
2. **Invite** the administrator from Settings → Organization → Members, as a member.
   `org/posthog` raises an existing member to admin; it cannot find someone who has not
   accepted, and the plan fails until they have.
3. **Create two personal API keys** under Account settings → Personal API keys, each
   limited to the `medusa` organization:

   | Key | Scopes |
   |---|---|
   | plan → `POSTHOG_PLAN_API_KEY` | `organization:read`, `organization_member:read`, `project:read`, `user:read` |
   | apply → `POSTHOG_APPLY_API_KEY` | the four above, plus `organization_member:write`, `project:write` |

   Store them from a terminal of your own (`gh secret set …`), never pasted anywhere else.
4. **Create the empty state** as the bootstrap admin, after `source .envrc.local`:

   ```sh
   cd terraform/live/org/posthog
   terraform init -backend-config="bucket=<management state bucket>"
   ```

   The first run of a new root writes an empty state object. The plan identity can read
   this prefix and write only its lock, so a first plan from CI is refused with
   `storage.objects.create` denied. That refusal is the design; the bootstrap admin
   creates the object once.

5. **Create the source-map key** for the app, under Account settings → Personal API keys:
   scopes `error_tracking:write` and `organization:read`, limited to the `medusa`
   organization, labelled `medusa source maps`. Terraform cannot create a personal key.
   It lives only in `apps/native/.env.dev` in `medusa-app`, on the Mac where the app is
   built, as `POSTHOG_CLI_API_KEY`, with the project ID as `POSTHOG_CLI_PROJECT_ID`. No
   GitHub secret holds it: the app has no build pipeline yet.

`org/posthog` also sets the project's settings: session replay on
(`session_recording_opt_in`) and client IPs discarded at ingestion (`anonymize_ips`).

**PostHog API keys are personal.** The three keys belong to **Fabiana Lula**, the organization's
owner, who signed up. Unlike the
Cloudflare tokens they cannot be owned by the organization: if that account leaves or loses
access, the keys stop working, and new ones must be made by another owner and swapped in.

**One project serves every environment.** `stg` and `prd` are not separate projects: the
environment travels on the data — `deployment.environment.name` on traces, `environment` on
log lines — and is a filter in PostHog, not a second project to keep in step.

## Secrets and state

**No secret value reaches a GCP state file.** Terraform creates secret containers, never
their contents; the tunnel token is fetched from the Cloudflare API by the deploy job and
written under an identity that can add a version to that one secret and cannot read it
back. The PostHog project token takes the same path: `_posthog-live-apply.yml` reads it from
the `org/posthog` state after the apply and adds it as a version of stg's
`medusa_stg_posthog_posthog-project-token`, as the federated identity of that apply, which
holds `secretVersionAdder` on that one secret. `stg-cd` creates the secret on the same push,
so the step retries the write every 20 seconds for up to ten minutes until it exists. The only value the GCP roots write into
state is the literal string `REPLACE_ME_VIA_SECRET_MANAGER`.

**What the VM reads before the app starts.** `cloudflared.service` fetches the tunnel token,
and `medusa-app.service` runs `/etc/medusa/write-app-env.sh` before every start. It writes
`/var/lib/medusa/app.env`, readable by root alone, which the container gets with
`--env-file`:

| Variable | Value |
|---|---|
| `POSTHOG_HOST` | `https://us.i.posthog.com` |
| `LOG_POSTHOG_LEVEL` | `warn` |
| `LOG_STDOUT` | `true` |
| `LOG_LEVEL` | `info` |
| `OTEL_TRACES_SAMPLER_ARG` | `1` in stg, `0.1` in prd (`otel_traces_sampler_arg` in each `<env>/gcp`) |
| `NODE_ENV` | `production` |
| `POSTHOG_PROJECT_TOKEN` | the latest version of `medusa_<env>_posthog_posthog-project-token`, only when it is real |

The token is optional: without it the API sends nothing to PostHog and runs the same. So
the script never stops the start. It writes the fixed values, then adds the token only when
Secret Manager answered within ten seconds with a value that is neither empty nor
`REPLACE_ME_VIA_SECRET_MANAGER`; otherwise it logs one line saying the token is absent.
Because the file is rewritten before every start, a restart picks up a new token version;
`backend-cd` in `medusa-app` restarts the app.

**One secret value does reach state**: the Cloudflare plan token,
`cloudflare_account_token.plan.value` in `org/cloudflare/_setup`, listed here because the
standard asks for exactly that. The mint token is made by hand and lives only in GitHub. Only the bootstrap admin can read
that prefix — the IAM conditions in `org/gcp/_setup` limit the GitHub identities of the
Cloudflare org stack to `org/cloudflare/live/`.

Terraform creates it, so its policy is a reviewable diff rather than something clicked in
a dashboard. That is the trade: a value in a state file nobody but the
bootstrap admin can read, against a permission nobody at all could review.

Marking an output `sensitive` keeps a value out of the logs. It does not encrypt it in
state — what protects these is the bucket: customer-managed key, versioned, and reachable
under that prefix by one identity.

> Secret Manager ids accept only `[a-zA-Z0-9_-]`, so the four-part name in the standard
> cannot use `/`. The parts are kept and joined with `_`:
> `medusa/stg/cloudflare/tunnel-token` → `medusa_stg_cloudflare_tunnel-token`.

## Human access

Sign in with your Google account. No keys are issued, to anyone, anywhere.

```sh
gcloud auth login
gcloud config set project protech-medusa-stg
gcloud compute instances list
```

Two roles, and nobody gets a shell:

| Role | Who | What it allows |
|---|---|---|
| read-only | the developer group | see everything — **never a secret value**, which is enforced by an IAM deny, not by the absence of a grant |
| administration | one named person, and whoever the member list gives the `administration` profile | full access on `stg` and `prd`, for what CI cannot do, including reading a secret value |

With read-only, stopping an instance, changing anything, or reading a secret value is
refused. Membership is managed in the Google Group, so adding or removing a developer is
not a code change and not a deploy.

**No role grants an IAP tunnel or OS Login.** That is deliberate rather than missing: a
shell on the box is the box's identity, and the box reads the tunnel-token and PostHog
token secrets because it needs them to start. Any human shell would therefore reach a secret
value, whatever the deny policy says, because the caller on that path is the VM and not the
person.

The administration role goes to named accounts and never to a group, so every change made
outside CI has an owner. It sits outside the deny policy — it is the role for the cases
nobody listed in advance.

The deny policy lives in `org/organization-member-access/gcp`, so only an approved run of
`organization-member-access-cd` changes or re-asserts it. `org/gcp/_setup` still grants the
group its read-only role.

### The member list

`ORG_MEMBERS_ACCESS` is a JSON object keyed by a short handle. Applying it needs an approved
run of `organization-member-access-cd`:

```json
{
  "handle": {
    "email": "person@example.com",
    "gcp": {
      "account": "only when the Google account's primary address differs from email",
      "stg": ["read_only", "administration", "logs"],
      "prd": ["read_only"]
    },
    "posthog": "member or admin"
  }
}
```

`org/organization-member-access/gcp` imports the group's deny policy, so it only applies where `org/gcp/_setup` already created that policy. A new organization has to create it by hand first, with the name `medusa-developers-no-secret-values`, because `org/gcp/_setup` no longer does.

A role in `stg` or `prd` is refused for any Google account outside the list, the
administrator and the developer group. The organization's identities stay admitted, which
is how CI keeps its roles. Taking a person off the list stops managing their PostHog level
and leaves them in the organization.

## Pipelines

| Workflow | When | What |
|---|---|---|
| `live-plan` | every PR | plans all nine stacks; changes under `.github/scripts/terraform/` also trigger the GCP, Cloudflare, PostHog and setup plans. `Plan stg`, `Plan prd` and the three `Plan … setup` always report, the Cloudflare and PostHog stacks only when touched. Each section links the full `plan.txt` in the plan store, which opens for a signed-in developer. A plan is never red because of the store: a failed upload is a warning, and the section then has no link. One comment, a section per stack — a stack whose plan failed is named, one out of scope gets no section, and the comment is deleted when no stack has a section at all |
| `code-quality` | every PR | fmt, validate, tflint, actionlint, shellcheck of `.github/scripts`, gitleaks, trivy → **Code Quality Summary** |
| `pr-template` | every PR, and when its title or body is edited | the title passes commitlint; every section of the base branch's template is filled and every checklist item is ticked or marked n/a; bots get the title check only → **Quality — PR Template** |
| `setup-cd` | merge to `dev` touching a GCP `_setup` root, a module it sources or `.github/scripts/terraform/**` | applies org, then stg, then prd, each after a required reviewer approves in the `setup` environment. `TF_APPLY_ENABLE_PRD` does not gate it: `prd/gcp/_setup` holds identities and access, not the workload |
| `stg-cd` | merge to `dev` | only the GCP apply waits for `setup-cd` when the push touched its paths; failed or cancelled setup runs block that apply, even for an older commit. Cloudflare runs in parallel and can apply while setup approval is pending or after setup fails. The tunnel token is written only after both applies succeed |
| `org-cd` | merge to `dev` | applies org Cloudflare and org PostHog, then writes the PostHog project token to stg's secret |
| `prd-cd` | every push | GCP, then Cloudflare once GCP succeeded. **Switched off** by `TF_APPLY_ENABLE_PRD` — shows as skipped |
| `organization-member-access-cd` | by hand from `dev` | applies the member list to GCP and PostHog, after a required reviewer approves in the `organization-member-access` environment |

Branch protection requires `Plan stg / plan`, `Plan prd / plan`, `Plan org setup / plan`,
`Plan stg setup / plan`, `Plan prd setup / plan`, `Code Quality Summary` and
`Quality — PR Template`.
A check that never runs counts as passed, which is why the plan jobs always run and why the
summary job exists at all.

Every apply runs `terraform apply` directly, which plans against the state at merge time:
the plan a reviewer approved was made against the state as it was *before* the merge.
