const $ = id => document.getElementById(id);
let latest, ready = false, running = false;
async function checkReady() {
  try {
    const state = await (await fetch('/health')).json();
    ready = state.ready;
    $('readiness').textContent = `Model: ${state.model} · ClickHouse: ${state.clickhouse}`;
    if (!running) {
      $('run').disabled = !ready;
      $('activity').textContent = ready ? 'Ready. Predict your winner first.' : 'Services are starting. The first model download can take several minutes.';
    }
  } catch {
    ready = false;
    $('readiness').textContent = 'Cannot reach the lab. Check docker compose ps, then refresh.';
    if (!running) $('run').disabled = true;
  }
}
function element(tag, text, className) {
  const node = document.createElement(tag);
  if (text !== undefined) node.textContent = text;
  if (className) node.className = className;
  return node;
}
function render(result) {
  latest = result;
  $('dashboard-heading').textContent = result.plan.dashboard_title;
  $('result-meta').textContent = `${result.plan.metric} by ${result.plan.group_by} · engaged ≥ ${result.plan.threshold_seconds / 60} minutes · ${result.elapsed_seconds}s locally`;
  $('rows').replaceChildren(); $('chart').replaceChildren(); $('trace').replaceChildren();
  const maximum = result.plan.metric === 'engagement_pct' ? 100 : Math.max(1, ...result.rows.map(row => Number(row[result.plan.metric])));
  for (const row of result.rows) {
    const tr = element('tr');
    for (const key of ['segment', 'starts', 'engaged_sessions', 'engagement_pct']) tr.append(element('td', typeof row[key] === 'number' ? row[key].toLocaleString() : row[key]));
    $('rows').append(tr);
    const barRow = element('div', undefined, 'bar-row');
    const track = element('div', undefined, 'bar-track');
    const fill = element('div', undefined, 'bar-fill');
    fill.style.width = `${100 * Number(row[result.plan.metric]) / maximum}%`;
    track.append(fill);
    const value = Number(row[result.plan.metric]).toLocaleString() + (result.plan.metric === 'engagement_pct' ? '%' : '');
    barRow.append(element('span', row.segment), track, element('strong', value));
    $('chart').append(barRow);
  }
  for (const step of result.trace) {
    const li = element('li');
    li.append(element('strong', step.tool), element('pre', typeof step.detail === 'string' ? step.detail : JSON.stringify(step.detail, null, 2)));
    $('trace').append(li);
  }
  $('observation').textContent = result.note.observation;
  $('limitation').textContent = result.note.limitation;
  $('next-test').textContent = result.note.next_test;
  $('sql').textContent = result.sql;
  $('result').hidden = false;
}
document.querySelectorAll('[data-prompt]').forEach(button => button.addEventListener('click', () => {
  $('prompt').value = button.dataset.prompt; $('prompt').focus();
}));
$('investigate').addEventListener('submit', async event => {
  event.preventDefault();
  if (running || !ready) return;
  running = true; $('run').disabled = true; $('error').hidden = true;
  const started = Date.now();
  const timer = setInterval(() => {
    $('activity').textContent = `Local model planning, querying and building… ${Math.floor((Date.now() - started) / 1000)}s. Small CPUs may take a minute.`;
  }, 1000);
  $('activity').textContent = 'Sending your question to the local agent…';
  try {
    const response = await fetch('/api/run', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({prompt: $('prompt').value})});
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || 'The investigation failed. Try again.');
    if (result.help) {
      $('error').textContent = result.help; $('error').hidden = false;
      $('activity').textContent = 'Choose a supported analytics question.';
    } else {
      render(result); $('activity').textContent = 'Dashboard built. Inspect the SQL, then challenge the interpretation.';
      $('result').scrollIntoView({behavior: 'auto', block: 'start'});
    }
  } catch (error) {
    $('error').textContent = error.message; $('error').hidden = false;
    $('activity').textContent = 'Investigation stopped. Your question is preserved; retry when ready.';
  } finally { clearInterval(timer); running = false; $('run').disabled = !ready; }
});
$('download').addEventListener('click', () => {
  if (!latest) return;
  const url = URL.createObjectURL(new Blob([latest.dashboard_html], {type: 'text/html;charset=utf-8'}));
  const link = element('a'); link.href = url; link.download = 'campusstream-dashboard.html'; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
checkReady(); setInterval(checkReady, 10000);
