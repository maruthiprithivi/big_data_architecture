const $ = id => document.getElementById(id);
const thresholds = [60, 600, 1200, 1800, 2400];
const labels = {starts: 'Starts', engaged_sessions: 'Engaged sessions', engagement_pct: 'Engagement rate'};
const stageMessages = {plan: 'Local model: choosing a typed query plan…', query: 'ClickHouse: executing validated, read-only SQL…', interpret: 'Local model: reflecting on verified evidence…', build: 'Building your chart and downloadable dashboard…'};
let latest, ready = false, running = false;
function element(tag, text, className) {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  if (className) node.className = className;
  return node;
}
function setControls() {
  for (const control of document.querySelectorAll('#experiment input, #experiment select, #prompt')) control.disabled = running;
  const predicting = $('group').value === 'title';
  for (const input of document.querySelectorAll('[name=prediction]')) {
    input.required = predicting; input.disabled = running || !predicting;
  }
  $('run').disabled = $('ask').disabled = running || !ready;
}
async function checkReady() {
  try {
    const response = await fetch('/health');
    if (!response.ok) throw new Error('Health check failed');
    const state = await response.json(); ready = state.ready;
    $('readiness').textContent = `Model: ${state.model} · ClickHouse: ${state.clickhouse}`;
    if (!running && !latest) $('activity').textContent = ready ? 'Ready. Choose your predicted winner.' : 'Services are starting. The first model download takes several minutes.';
  } catch {
    ready = false; $('readiness').textContent = 'Cannot reach the lab. Check docker compose ps, then refresh.';
  }
  setControls();
}
function progress(stage) {
  const nodes = [...document.querySelectorAll('[data-stage]')];
  const current = nodes.findIndex(node => node.dataset.stage === stage);
  for (const [index, node] of nodes.entries()) {
    const active = index === current;
    const passed = stage === 'complete' || (current >= 0 && index < current);
    node.classList.toggle('done', passed); node.classList.toggle('active', active);
    node.querySelector('.stage-state').textContent = passed ? '✓ Done' : active ? '● Working' : 'Waiting';
  }
  if (stageMessages[stage]) $('activity').textContent = stageMessages[stage];
}
function render(result, prediction, requested) {
  latest = result;
  const {metric, group_by: group, threshold_seconds: threshold} = result.plan;
  $('dashboard-heading').textContent = `${labels[metric]} by ${group === 'title' ? 'movie title' : group}`;
  $('result-meta').textContent = `1,000,000 synthetic sessions · engaged ≥ ${threshold / 60} minutes · ${result.elapsed_seconds}s locally`;
  $('rows').replaceChildren(); $('chart').replaceChildren(); $('trace').replaceChildren();
  $('chart').classList.toggle('many-rows', result.rows.length > 4);
  const top = Math.max(...result.rows.map(row => Number(row[metric])));
  const leaders = result.rows.filter(row => Number(row[metric]) === top).map(row => row.segment);
  const maximum = metric === 'engagement_pct' ? 100 : Math.max(1, top);
  for (const row of result.rows) {
    const tr = element('tr');
    for (const key of ['segment', 'starts', 'engaged_sessions', 'engagement_pct']) tr.append(element('td', typeof row[key] === 'number' ? row[key].toLocaleString() : row[key]));
    $('rows').append(tr);
    const barRow = element('div', undefined, 'bar-row' + (leaders.includes(row.segment) ? ' leader' : ''));
    const track = element('div', undefined, 'bar-track'), fill = element('div', undefined, 'bar-fill');
    fill.style.width = `${100 * Number(row[metric]) / maximum}%`; track.append(fill);
    const value = Number(row[metric]).toLocaleString() + (metric === 'engagement_pct' ? '%' : '');
    barRow.append(element('span', row.segment), track, element('strong', value)); $('chart').append(barRow);
  }
  const tied = leaders.length > 1;
  const matched = group === 'title' && leaders.includes(prediction);
  const headline = tied ? `A tie: ${leaders.length} segments share the lead.` : `${leaders[0]} leads on ${labels[metric].toLowerCase()}.`;
  let feedback = group === 'title' ? `${matched ? 'Your prediction matched' : 'You predicted ' + prediction + '. Reconsider'} — would another measure change your choice?` : 'A different grouping answers a different business question. What detail did aggregation hide?';
  if (group === 'title' && !prediction) feedback = 'Pick a title before your next run. Would another success measure change your choice?';
  if (tied && top === 0) feedback = 'No session cleared this threshold. Zero engagement does not identify a winning title.';
  if (requested && (metric !== requested.metric || group !== requested.group || threshold !== requested.threshold)) feedback = 'The model chose different settings from your request. Inspect its plan before trusting this result.';
  $('decision').classList.toggle('match', matched && !tied);
  $('decision').replaceChildren(element('strong', headline), element('p', feedback));
  for (const step of result.trace) {
    const li = element('li'); li.append(element('strong', step.tool), element('pre', typeof step.detail === 'string' ? step.detail : JSON.stringify(step.detail, null, 2))); $('trace').append(li);
  }
  $('observation').textContent = result.note.observation; $('limitation').textContent = result.note.limitation;
  $('next-test').textContent = result.note.next_test; $('sql').textContent = result.sql;
  $('download').disabled = false;
}
async function investigate(prompt, prediction, requested) {
  if (running || !ready) return;
  const trigger = document.activeElement;
  running = true; setControls(); $('error').hidden = true; progress('idle');
  $('activity').textContent = 'Sending your question to the local agent…';
  let received = false;
  try {
    const response = await fetch('/api/run', {method: 'POST', headers: {'Content-Type': 'application/json', Accept: 'application/x-ndjson'}, body: JSON.stringify({prompt})});
    if (!response.ok) { const failure = await response.json(); throw new Error(failure.error || 'The investigation failed.'); }
    const reader = response.body.getReader(), decoder = new TextDecoder(); let buffer = '';
    function accept(line) {
      if (!line.trim()) return;
      const event = JSON.parse(line);
      if (event.error) throw new Error(event.error);
      if (event.stage) progress(event.stage);
      if (event.result) {
        received = true;
        if (event.result.help) throw new Error(event.result.help);
        render(event.result, prediction, requested); progress('complete');
        $('activity').textContent = 'Evidence ready. Change one setting, predict again, then rerun.';
      }
    }
    while (true) {
      const {value, done} = await reader.read();
      buffer += decoder.decode(value, {stream: !done});
      const lines = buffer.split('\n'); buffer = lines.pop(); lines.forEach(accept);
      if (done) { accept(buffer); break; }
    }
    if (!received) throw new Error('The connection ended before evidence arrived. Retry the experiment.');
  } catch (error) {
    $('error').textContent = error.message; $('error').hidden = false;
    $('activity').textContent = 'Experiment stopped. Your settings are preserved; retry when ready.';
    for (const node of document.querySelectorAll('.pipeline .active')) { node.classList.remove('active'); node.querySelector('.stage-state').textContent = 'Stopped'; }
  } finally {
    running = false; setControls();
    if (trigger?.id === 'run' || trigger?.id === 'ask') trigger.focus({preventScroll: true});
  }
}
$('experiment').addEventListener('submit', event => {
  event.preventDefault();
  const metric = document.querySelector('[name=metric]:checked').value;
  const group = $('group').value, threshold = thresholds[Number($('threshold').value)];
  const prediction = document.querySelector('[name=prediction]:checked')?.value;
  investigate(`Compare ${metric} by ${group}, using a ${threshold / 60}-minute threshold. Build a dashboard.`, prediction, {metric, group, threshold});
});
$('investigate').addEventListener('submit', event => { event.preventDefault(); investigate($('prompt').value, document.querySelector('[name=prediction]:checked')?.value); });
$('experiment').addEventListener('input', () => {
  const minutes = thresholds[Number($('threshold').value)] / 60;
  $('threshold-value').textContent = `${minutes} ${minutes === 1 ? 'minute' : 'minutes'}`;
  $('threshold').setAttribute('aria-valuetext', $('threshold-value').textContent);
  if (latest && !running) $('activity').textContent = 'Settings changed. Chart shows the previous run — reveal the evidence to update it.';
  setControls();
});
$('download').addEventListener('click', () => {
  if (!latest) return;
  const url = URL.createObjectURL(new Blob([latest.dashboard_html], {type: 'text/html;charset=utf-8'}));
  const link = element('a'); link.href = url; link.download = 'campusstream-dashboard.html'; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
checkReady(); setInterval(checkReady, 10000);
