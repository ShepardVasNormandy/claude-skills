#!/usr/bin/env node
// Usage: route.mjs [--orchestrator] [--tool <claude-code|codex>] "<task description>"   (default tool: claude-code)
// --orchestrator caps the tier at intense: the orchestrator reads the whole thread, frontier there multiplies the cost.
// Sends the text to Jev with the questions of ../references/questions.json plus one `agent` choice
// built from ../agents/*.md, then maps the answers to a model through ../references/profiles.json.
// Prints {"fallback":true} and exits 0 when TYPESAFE_API_KEY is unset or Jev answers 402: the caller routes by itself.
// Any other non-2xx prints {"error":"Jev answered <status>"} and exits 0: the caller routes by itself and says the router was unavailable.
import { readdir, readFile } from 'node:fs/promises';
import { realpathSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SKILL = join(dirname(fileURLToPath(import.meta.url)), '..');
const REFERENCES = join(SKILL, 'references');
const AGENTS = join(SKILL, 'agents');
const EFFORTS = ['low', 'medium', 'high', 'xhigh'];

const RUNNER_UP_MIN = 0.2;
const round = (n) => Number(n.toFixed(2));

// Highest effort the tool's model accepts at or below the wanted one, null when it has no effort setting.
// `runner_up` appears when another tier got at least RUNNER_UP_MIN of the probability: a close call.
// With `orchestrator`, a frontier answer becomes intense and its probability is added to intense.
export function pick(answers, profile, { orchestrator = false } = {}) {
  const cap = (t) => (orchestrator && t === 'frontier' ? 'intense' : t);
  const tier = cap(answers.tier.choice);
  if (!profile[tier]) throw new Error(`profile has no tier "${tier}"`);
  const { model, efforts } = profile[tier];
  const wanted = EFFORTS.indexOf(answers.effort.choice);
  const effort = efforts.filter((e) => EFFORTS.indexOf(e) <= wanted).at(-1) ?? null;

  const probabilities = {};
  for (const [t, p] of Object.entries(answers.tier.probabilities ?? {})) probabilities[cap(t)] = (probabilities[cap(t)] ?? 0) + p;
  const result = { tier, model, effort, probability: round(probabilities[tier] ?? 1) };
  const [second, p] = Object.entries(probabilities)
    .filter(([t]) => t !== tier && profile[t])
    .sort((a, b) => b[1] - a[1])[0] ?? [];
  if (p >= RUNNER_UP_MIN) result.runner_up = { tier: second, model: profile[second].model, probability: round(p) };
  return result;
}

// name -> description, read from the front matter of each agents/*.md. The description is the Jev criterion.
export function parseAgent(md) {
  const front = md.match(/^---\n([\s\S]*?)\n---/)?.[1] ?? '';
  const field = (k) => front.match(new RegExp(`^${k}:\\s*(.+)$`, 'm'))?.[1].trim();
  return { name: field('name'), description: field('description') };
}

export async function loadAgents(dir = AGENTS) {
  const files = (await readdir(dir)).filter((f) => f.endsWith('.md'));
  const agents = {};
  for (const f of files) {
    const { name, description } = parseAgent(await readFile(join(dir, f), 'utf8'));
    if (!name || !description) throw new Error(`agents/${f} needs a name and a description`);
    agents[name] = description;
  }
  return agents;
}

const agentQuestion = (agents) => ({
  type: 'choice',
  instructions: 'Pick the one type of work the task in `task` asks for. Judge the task as written. Do not solve it.',
  criteria: agents,
});

export async function route(text, profile, questions, agents, { fetch, key, base, orchestrator = false }) {
  const res = await fetch(`${base}/v1/systemone`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ state: { task: text }, model: 'jev-latest', questions: { ...questions, agent: agentQuestion(agents) } }),
    signal: AbortSignal.timeout(30_000),
  });
  if (res.status === 402) return { fallback: true, status: 402 };
  if (!res.ok) return { error: `Jev answered ${res.status}` };
  const { answers } = await res.json();
  const agent = answers.agent.choice;
  return { ...pick(answers, profile, { orchestrator }), agent, agent_description: agents[agent] };
}

async function main() {
  try {
    const args = process.argv.slice(2);
    const flag = args.indexOf('--tool');
    const tool = (flag >= 0 ? args.splice(flag, 2)[1] : process.env.MODEL_ROUTER_TOOL) ?? 'claude-code';
    const orchestratorFlag = args.indexOf('--orchestrator');
    const orchestrator = orchestratorFlag >= 0;
    if (orchestrator) args.splice(orchestratorFlag, 1);
    const text = args.join(' ').trim();
    const key = process.env.TYPESAFE_API_KEY;
    if (!text) throw new Error('usage: route.mjs [--orchestrator] --tool <claude-code|codex> "<task description>"');
    if (!key) {
      console.log(JSON.stringify({ fallback: true }));
      return;
    }

    const readJson = async (file) => JSON.parse(await readFile(join(REFERENCES, file), 'utf8'));
    const profiles = await readJson('profiles.json');
    if (!profiles[tool]) throw new Error(`--tool must be one of: ${Object.keys(profiles).join(', ')}`);

    const base = process.env.TYPESAFE_BASE_URL || 'https://api.typesafe.ai';
    const result = await route(text, profiles[tool], await readJson('questions.json'), await loadAgents(), { fetch, key, base, orchestrator });
    console.log(JSON.stringify(result));
  } catch (e) {
    console.log(JSON.stringify({ error: e.message }));
    process.exitCode = 1;
  }
}

// realpath: the skills CLI installs by symlink, argv[1] may be the link and import.meta.url the target
if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) main();
