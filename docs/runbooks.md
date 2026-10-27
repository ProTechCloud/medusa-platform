# Runbooks

What to do when something is wrong. Each one starts from the symptom you
actually have — an alert in your inbox, a red job, an error in a terminal —
and not from the part of the system at fault, because at the start you do not
know which part that is.

Two rules hold across all of them:

1. **Read before you change.** Every command that reads is safe to run twice.
   The ones that change are marked, and each says what it breaks if the
   diagnosis was wrong.
2. **Nothing is fixed in a console.** A change clicked in the Cloud or
   Cloudflare console is invisible to review and is reverted by the next apply,
   silently. The exceptions are the hand-made credentials, which have no
   Terraform resource at all: the Cloudflare master and bootstrap tokens, and
   the secret *values*. Those are listed where they come up.

Who can run what: the commands that reach the VM or write state need the
administration role, or the bootstrap admin identity from `.envrc.local`.
Members of the developer group can read everything here and change nothing —
that is the point of that role, not a gap in it.

---

## The API is down

**You get:** `medusa stg: API is not answering /health`, or a request to
`https://api-stg-medusa.<domain>` that fails.

### 1. Ask the edge or the box

```sh
curl -s -o /dev/null -w '%{http_code}\n' https://api-stg-medusa.<domain>/health
```

The status code splits the problem in two, and the two halves have nothing in
common:

| Code | What it means | Go to |
|---|---|---|
| `530` or a Cloudflare 1033 page | Cloudflare is up, the tunnel is not connected | step 3 |
| `502`, `503` | the tunnel is connected, the application behind it is not answering | step 4 |
| `200` | it recovered on its own | step 5 |
| nothing, a DNS error | the record is gone, or the zone is | step 6 |

### 2. Is the VM running at all

```sh
gcloud compute instances describe medusa-stg \
  --zone=us-central1-a --project=protech-medusa-stg \
  --format='value(status)'
```

`TERMINATED` means the instance stopped. `RUNNING` with a broken service means
the box is up and something on it is not.

### 3. The tunnel is not connected

Get on the box. There is no SSH port open to the internet; the session goes
through IAP, which is why this needs the administration role:

```sh
gcloud compute ssh medusa-stg \
  --zone=us-central1-a --project=protech-medusa-stg --tunnel-through-iap
```

Then:

```sh
sudo systemctl status cloudflared.service
sudo journalctl -u cloudflared.service -n 100 --no-pager
```

The failure that is not obvious from the logs: the connector authenticates
with the tunnel token in Secret Manager, and that token is written by the
deploy job, not by Terraform. If the logs show an authentication failure, the
stored token no longer matches the tunnel — re-run `stg-cd` from the Actions
tab, which writes a fresh one and restarts the connector.

### 4. The application is not answering

On the box:

```sh
sudo systemctl status medusa-app.service
sudo journalctl -u medusa-app.service -n 100 --no-pager
sudo docker ps -a
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/health
```

If `/health` answers on the loopback but not through Cloudflare, the
application is fine and the tunnel is not — go back to step 3.

**Changes anything:** restarting the container loses whatever it held in
memory and nothing else, because the image and its configuration come from the
registry and the secret on every start:

```sh
sudo systemctl restart medusa-app.service
```

If the box itself is wedged, resetting it re-runs cloud-init, which logs in to
the registry, pulls the image the last deploy published and starts both
services:

```sh
gcloud compute instances reset medusa-stg \
  --zone=us-central1-a --project=protech-medusa-stg
```

This is a hard power cycle. It is safe here only because the instance holds no
state worth keeping — every byte it needs comes from somewhere else at boot.

### 5. It recovered on its own

Still worth a look, because an alert that resolves itself usually resolves
itself again at a worse time. In the Cloud console, Monitoring → Uptime
checks → `medusa stg api` shows which regions failed and for how long. A
single region for a few minutes is the internet; every region at once is the
service.

### 6. The hostname does not resolve

The record and the tunnel are Terraform's, in `terraform/live/stg/cloudflare`.
Check the last `stg-cd` run, and run a plan on the branch: if the plan wants to
create the record, something deleted it outside Terraform and applying puts it
back.

---

## An apply failed

**You get:** a red `apply stg gcp`, `apply stg cloudflare`, `apply org
cloudflare` or `apply prd gcp` job.

Open the job log and find the first error, not the last one — Terraform keeps
going after a failure on an unrelated resource, so the end of the log is often
a consequence.

Three kinds, with different fixes:

**A 403, or `Permission ... denied`.** The identity the job acts as is missing
a role. That is not fixable in this pull request's code path: every CI
permission is defined in a `_setup` root, which CI cannot apply. Add the role
there, get it reviewed, and apply that root by hand:

```sh
source .envrc.local
cd terraform/live/stg/gcp/_setup
terraform apply -input=false
```

**`already exists`.** Something exists in the cloud that Terraform has no
record of — usually created by hand, or left behind by a half-finished apply.
Either import it, so Terraform adopts the real thing:

```sh
terraform import '<address>' '<id>'
```

or delete the real thing and let the apply create it. Importing is the right
default; deleting is for resources you are certain nothing depends on.

**A provider or API error.** Read it literally. `API has not been used in
project ... before or it is disabled` means the API is missing from the `apis`
list in `org/gcp/_setup`, and the fix is there.

**What not to do:** do not edit the state file to make an error go away. A
re-run is safe. Terraform recorded everything it created before it failed, so
the second run picks up where the first stopped, and a half-applied stack is a
normal state to re-apply from — not something to repair by hand.

If the failed run also left a lock behind, the next runbook.

---

## A state lock is stuck

**You get:** `Error acquiring the state lock`, with a `Lock Info` block naming
an ID, who took it and when.

### 1. Make sure nothing is still running

The lock usually belongs to a run that died, but if it belongs to one that is
alive, breaking it means two applies writing one state file — which is how a
state file ends up describing infrastructure that does not exist.

Check the Actions tab for a run in progress on that environment. Plans and
applies are queued one at a time per environment and are never cancelled, so a
second one cannot start while the first holds the lock. If a run is in
progress, wait for it: this is not a stuck lock, it is a queue.

### 2. Break it

With the ID from the error message, from the root that is stuck:

```sh
source .envrc.local
cd terraform/live/stg/gcp
terraform init -lockfile=readonly \
  -backend-config="bucket=$(gh variable get STATE_BUCKET_STG)"
terraform force-unlock <lock id>
```

If `force-unlock` cannot run — a corrupted lock object, an init that fails for
its own reasons — delete the object directly. The GCS backend's lock is one
object next to the state:

```sh
gcloud storage rm "gs://$(gh variable get STATE_BUCKET_STG)/stg/gcp/live/default.tflock"
```

**Changes anything:** both commands only remove the lock. Neither touches the
state. The risk is entirely in step 1.

State lives here, when you need to name the object:

| Root | Bucket (GitHub variable) | Prefix |
|---|---|---|
| `org/gcp/_setup` | `MANAGEMENT_STATE_BUCKET` | `org/gcp/setup` |
| `stg/gcp/_setup`, `prd/gcp/_setup` | `MANAGEMENT_STATE_BUCKET` | `<env>/gcp/setup` |
| `org/cloudflare/_setup` | `MANAGEMENT_STATE_BUCKET` | `org/cloudflare/setup` |
| `org/cloudflare` | `MANAGEMENT_STATE_BUCKET` | `org/cloudflare/live` |
| `stg/cloudflare`, `prd/cloudflare` | `MANAGEMENT_STATE_BUCKET` | `<env>/cloudflare` |
| `stg/gcp` | `STATE_BUCKET_STG` | `stg/gcp/live` |
| `prd/gcp` | `STATE_BUCKET_PRD` | `prd/gcp/live` |

---

## Changing a Cloudflare token

There are three long-lived tokens and one kind made per job. Which one you are
replacing decides everything about how.

| Token | Where it lives | Made by |
|---|---|---|
| plan | `CLOUDFLARE_PLAN_TOKEN`, repository secret | Terraform, in `org/cloudflare/_setup` |
| master | `CLOUDFLARE_MINT_TOKEN`, environment secret on `stg`, `prd`, `cloudflare-org` | by hand, in the dashboard |
| bootstrap | `.envrc.local` on one laptop, never in GitHub | by hand, in the dashboard |
| per-job write | nowhere — created and deleted inside one apply job | the master token |

**The order is always: put the new value in place, then revoke the old one.**
Revoking first means every job that starts in between fails, and for the plan
token that is every pull request.

### The plan token

Terraform owns it, so replacing it is an apply:

```sh
source .envrc.local
cd terraform/live/org/cloudflare/_setup
terraform apply -input=false -replace=cloudflare_account_token.plan
terraform output -raw plan_token | gh secret set CLOUDFLARE_PLAN_TOKEN
```

`-replace` creates the new token and destroys the old one in the same apply, so
there is nothing left to revoke by hand. Piping the value rather than copying
it keeps it out of the terminal scrollback and out of your shell history.

### The master token

This is the one Cloudflare will not let Terraform create — it refuses to mint a
token that can manage tokens — so it is made in the dashboard: **Manage
Account → API Tokens → Create Token → Create Additional Tokens** template,
which is `Account API Tokens Write` and nothing else. Under *Manage Account*,
not *My Profile*: a token made under My Profile belongs to a person and stops
working when that person leaves.

Then, for each environment that applies Cloudflare:

```sh
gh secret set CLOUDFLARE_MINT_TOKEN --env stg
gh secret set CLOUDFLARE_MINT_TOKEN --env prd
gh secret set CLOUDFLARE_MINT_TOKEN --env cloudflare-org
```

Only then revoke the old token in the dashboard.

### The bootstrap token

Same template and same place as the master token, pasted into `.envrc.local`.
It is deliberately separate from the master token even though the policy is
identical: one lives in CI, one lives with a person, and they are rotated for
different reasons — a CI secret because time passed, a personal credential
because a laptop or a person changed.

### An orphaned per-job token

Each apply job creates a write token, uses it, and deletes it in a step that
runs even when the job fails. A job killed outright — a cancelled run, a
runner that vanished — can leave one behind. They are named with the run that
created them, so they are easy to spot in **Manage Account → API Tokens**:
delete any whose run has finished.

---

## Going back to an older state version

**Use this when** an apply wrote a state file that no longer describes
reality — a destroy that should not have happened, a file truncated by a
crashed run.

**Understand first what this does not do.** Restoring state does not undo
anything in the cloud. It changes Terraform's *record* of the cloud. If an
apply destroyed a bucket, putting back yesterday's state does not put back the
bucket; it makes Terraform believe the bucket exists, and the next plan will
disagree with reality in a new way. Restoring state is the right move when the
*record* is wrong, not when the *infrastructure* is.

Every state bucket keeps old versions for 90 days.

### 1. Take the lock, or make sure nobody else can write

Restoring under a running apply loses either your restore or its work. The
safest sequence is to restore when no run is in flight, and to check the
Actions tab first.

### 2. Find the version you want

```sh
BUCKET="$(gh variable get STATE_BUCKET_STG)"
gcloud storage ls -a --long "gs://$BUCKET/stg/gcp/live/default.tfstate"
```

Each line is a generation number and a timestamp. Read one before you restore
it — the serial and lineage at the top tell you which run wrote it:

```sh
gcloud storage cat "gs://$BUCKET/stg/gcp/live/default.tfstate#<generation>" | head -20
```

### 3. Put it back

**Changes anything:** this overwrites the current state. The current version is
itself kept as a version, so this is reversible by repeating the step with the
newer generation.

```sh
gcloud storage cp \
  "gs://$BUCKET/stg/gcp/live/default.tfstate#<generation>" \
  "gs://$BUCKET/stg/gcp/live/default.tfstate"
```

### 4. Plan, and read it properly

```sh
source .envrc.local
cd terraform/live/stg/gcp
terraform init -lockfile=readonly -backend-config="bucket=$BUCKET"
terraform plan -input=false
```

Expect a plan that wants to create things that already exist, or to adopt them.
Each one tells you something about what diverged. Import what exists, and do
not apply a plan with a destroy in it until you can say why that destroy is
correct.
