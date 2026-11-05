module.exports = async ({ github, context, core }) => {
  const fs = require('fs')
  const path = require('path')

  const MARKER = '<!-- medusa-plan -->'
  // A GitHub comment body caps at 65536 characters, and this is
  // the ceiling for the whole comment — scaffolding included, not
  // just the plans inside it. Cutting here rather than per stack is
  // the point: five sections each cut at 60k would be rejected by
  // the API as one oversized comment.
  const BUDGET = 55000

  // Also the authoritative list of stacks, and the order they are
  // read in: environments first, then the edge, then the SaaS roots.
  const STACKS = [
    'gcp-stg', 'gcp-prd',
    'cloudflare-org', 'cloudflare-stg', 'cloudflare-prd',
    'posthog-org',
    'setup-org', 'setup-stg', 'setup-prd',
  ]
  const label = key => {
    const [provider, env] = key.split('-')
    return `${env} (${provider})`
  }

  const results = JSON.parse(process.env.RESULTS)
  const read = key => {
    const file = path.join('plans', `plan-${key}`, 'plan.txt')
    return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null
  }
  // Written beside plan.txt once it is in the plan store. It opens for a
  // signed-in developer. The file comes from a job that runs pull-request code,
  // so only a plain link into our own bucket reaches the comment.
  const readUrl = key => {
    const file = path.join('plans', `plan-${key}`, 'plan-url.txt')
    if (!fs.existsSync(file)) return null
    const url = fs.readFileSync(file, 'utf8').trim()
    const prefix = `https://storage.cloud.google.com/${process.env.PLAN_STORE_BUCKET}/`
    return url.startsWith(prefix) && /^[\w./-]+$/.test(url.slice(prefix.length)) ? url : null
  }

  // Three states per stack: it planned, it failed, or it was not
  // touched. Only the last one means "say nothing".
  const sections = []
  for (const key of STACKS) {
    const plan = read(key)
    if (plan !== null) {
      sections.push({ key, plan, url: readUrl(key) })
    } else if (results[key] && results[key].result === 'failure') {
      sections.push({ key, plan: null })
    }
  }

  if (sections.length === 0) {
    core.info('no stack in scope — the comment should not exist')
  }

  const render = (s, shown, cut) => {
    if (s.plan === null) {
      return [`### ${label(s.key)}`, '', '**The plan failed.** Read the job log.', '']
    }
    const notice = cut ? `\n> Output cut. Read the full plan at the link.` : ''
    const link = s.url ? `[Full plan](${s.url})` : '_No link to the full plan — see the log._'
    // Counted from the full plan, never from the truncated copy.
    // Terraform prints `Plan: …` as its last line, so cutting the
    // body removes exactly the summary a reviewer needs most — and
    // a large plan is the case where the cut happens.
    const m = s.plan.match(/Plan: (\d+) to add, (\d+) to change, (\d+) to destroy/)
    const summary = m
      ? `**${m[1]}** to add · **${m[2]}** to change · **${m[3]}** to destroy`
      : (/No changes/.test(s.plan) ? '**No changes.**' : '_Counts unavailable — see the log._')
    return [
      `### ${label(s.key)}`,
      '',
      summary,
      link,
      notice,
      '',
      // open: the diff is the thing a reviewer came to read.
      // Collapsed by default, approving without expanding it is one
      // click, and the comment stops being a gate and becomes
      // decoration.
      '<details open><summary>Full plan</summary>',
      '',
      '```terraform',
      shown,
      '```',
      '',
      '</details>',
      '',
    ]
  }

  const assemble = each => [MARKER, '## Terraform plan', '']
    .concat(...sections.map(each))
    .join('\n')

  // What the comment costs before a line of plan text goes into it:
  // the marker, the headings, the counts, the fences, the details
  // blocks. The budget is on the whole comment, so this comes off
  // the top — dividing BUDGET among the plans alone put the comment
  // over it by the size of its own scaffolding.
  //
  // The cut notice is counted for every section that planned, even
  // the ones that will not be cut. A section that keeps its whole
  // plan costs less than this, never more, which is what makes the
  // final length an upper bound rather than an estimate.
  const overhead = assemble(s => render(s, '', s.plan !== null)).length

  // Give every section what is left, smallest first, and let the
  // unused share flow to the ones that are too long. Splitting the
  // budget evenly would truncate a large plan while a one-line
  // "No changes." section sat on an unused 11k.
  const planned = sections.filter(s => s.plan !== null)
  const order = planned.map((s, i) => i)
    .sort((a, b) => planned[a].plan.length - planned[b].plan.length)
  let left = Math.max(BUDGET - overhead, 0)
  let share = order.length
  for (const i of order) {
    const allowance = Math.floor(left / share)
    const take = Math.min(planned[i].plan.length, allowance)
    planned[i].allowance = take
    left -= take
    share -= 1
  }

  const body = assemble(s => {
    if (s.plan === null) return render(s, null, false)
    const cut = s.plan.length > s.allowance
    return render(s, cut ? s.plan.slice(0, s.allowance) : s.plan, cut)
  })

  // Paginated on purpose. One page of 100 was the bug this replaces:
  // past that, bot reviews push the marker off the first page, the
  // upsert finds nothing, and every push adds another comment.
  const issue = {
    owner: context.repo.owner,
    repo: context.repo.repo,
    issue_number: context.issue.number,
  }
  const comments = await github.paginate(
    github.rest.issues.listComments, { ...issue, per_page: 100 },
  )
  const mine = c => c.user.type === 'Bot' && c.body.includes(MARKER)
  const existing = comments.find(mine)

  if (sections.length === 0) {
    if (existing) {
      await github.rest.issues.deleteComment({
        owner: issue.owner, repo: issue.repo, comment_id: existing.id,
      })
    }
  } else if (existing) {
    await github.rest.issues.updateComment({
      owner: issue.owner, repo: issue.repo, comment_id: existing.id, body,
    })
  } else {
    await github.rest.issues.createComment({ ...issue, body })
  }

  // One comment per stack is what this workflow replaced. Clearing
  // the old ones here means the change takes effect on the pull
  // request that introduces it, rather than leaving five orphans
  // nothing will ever update again.
  const legacy = comments.filter(
    c => c.user.type === 'Bot' && c.body.includes('<!-- medusa-plan:'),
  )
  for (const c of legacy) {
    await github.rest.issues.deleteComment({
      owner: issue.owner, repo: issue.repo, comment_id: c.id,
    })
  }
}
