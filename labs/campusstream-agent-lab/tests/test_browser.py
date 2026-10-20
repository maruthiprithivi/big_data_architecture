"""Optional maintainer UI E2E; uses chrome-devtools-axi and a running real lab."""
import json
import os
from pathlib import Path
import re
import subprocess
import time

BASE = os.environ.get("LAB_URL", "http://localhost:8090")
OUT = Path(os.environ.get("LAB_UI_OUTPUT", "/tmp/campusstream-ui"))
OUT.mkdir(parents=True, exist_ok=True)

def browser(*args):
    command = subprocess.run(["rtk", "proxy", "chrome-devtools-axi", *args], capture_output=True, text=True, check=True)
    return command.stdout

def evaluate(code):
    output = browser("eval", code)
    value = json.loads(re.search(r"^result: (.+)$", output, re.M)[1])
    if isinstance(value, str):
        try:
            return json.loads(value)
        except ValueError:
            pass
    return value

def click(role, name):
    snapshot = browser("snapshot")
    match = re.search(r'uid=(\S+) ' + role + r' "' + re.escape(name) + r'"', snapshot)
    assert match, (role, name)
    browser("click", "@" + match[1])

def reveal(expected):
    click("button", "Reveal the evidence")
    deadline = time.monotonic() + 180
    while not evaluate('() => !document.querySelector("#run").disabled'):
        assert time.monotonic() < deadline, "Investigation timed out"
        time.sleep(.2)
    actual = evaluate('() => ({error:document.querySelector("#error").hidden ? null : document.querySelector("#error").textContent, decision:document.querySelector("#decision").innerText, rows:document.querySelector("#rows").textContent, done:document.querySelectorAll("[data-stage].done").length, scroll:scrollY})')
    assert not actual["error"], actual
    assert expected in actual["decision"], actual
    assert actual["done"] == 4 and actual["scroll"] == 0, actual
    return actual

browser("open", BASE)
browser("resize", "1440", "970")
click("radio", "The Matrix")
results = [reveal("The Matrix leads")]
assert "500,000" in results[-1]["rows"]
click("radio", "Engaged sessions Who kept the most sessions watching?")
results.append(reveal("Apollo 13 leads"))
assert "240,000" in results[-1]["rows"]
click("radio", "Engagement rate What share stayed to watch?")
results.append(reveal("Cloud Atlas leads"))
assert "90" in results[-1]["rows"]
browser("screenshot", str(OUT / "engagement-rate.png"))
click("slider", "Engaged means at least")
browser("press", "ArrowRight")
assert evaluate('() => document.querySelector("#threshold-value").textContent') == "30 minutes"
results.append(reveal("Cloud Atlas leads"))
click("slider", "Engaged means at least")
browser("press", "End")
assert evaluate('() => document.querySelector("#threshold-value").textContent') == "40 minutes"
results.append(reveal("A tie: 4 segments"))
assert "Zero engagement" in results[-1]["decision"]
browser("screenshot", str(OUT / "threshold-tie.png"))
click("DisclosureTriangle", "Inspect the plan, SQL & exact rows")
assert evaluate('() => document.querySelector("#query-details").open && document.querySelector("#sql").textContent.includes("watch_seconds >= 2400")')
click("DisclosureTriangle", "Inspect the plan, SQL & exact rows")
evaluate('() => {window.downloadText=null;const original=URL.createObjectURL;URL.createObjectURL=blob=>{blob.text().then(text=>window.downloadText=text);return original(blob);};return true;}')
click("button", "Save dashboard")
assert evaluate('() => window.downloadText.includes("Executed SQL") && window.downloadText.includes("Qwen2.5")')
responsive=[]
for width in (320,768,1024,1440):
    browser("resize", str(width), "970")
    state=evaluate('() => ({width:innerWidth, content:document.documentElement.scrollWidth, runVisible:!!document.querySelector("#run").getClientRects().length})')
    assert state["content"] <= state["width"] and state["runVisible"], state
    responsive.append(state)
    browser("screenshot", str(OUT / f"responsive-{width}.png"))
browser("press", "Tab")
assert evaluate('() => document.activeElement.tagName !== "BODY"')
console=browser("console", "--type", "error")
assert '<no console messages found>' in console, console
receipt={"url":BASE,"cases":results,"responsive":responsive,"download":"actual browser Blob contains SQL + model attribution","console":console}
(OUT / "browser-e2e.json").write_text(json.dumps(receipt,indent=2))
print("PASS real UI: prediction, three rankings, threshold tie, SQL disclosure, download, four responsive widths, keyboard focus, console")
