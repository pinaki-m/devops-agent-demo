import json
import os
import socket
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("PORT", 80))


def _get_task_metadata():
    uri = os.environ.get("ECS_CONTAINER_METADATA_URI_V4")
    if not uri:
        return {}
    try:
        with urllib.request.urlopen(f"{uri}/task", timeout=2) as r:
            return json.loads(r.read())
    except Exception:
        return {}


HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Cosmic Creature Shelter</title>
<style>
  :root {
    --bg: #0a0a1a;
    --surface: #12122a;
    --border: #2a2a4a;
    --text: #e8e8ff;
    --muted: #7070a0;
    --yellow: #ffd700;
    --purple: #b06aff;
    --pink: #ff6ab0;
    --cyan: #6af0ff;
    --green: #6affa0;
    --orange: #ffaa6a;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background: var(--bg);
    color: var(--text);
    font-family: 'Segoe UI', system-ui, sans-serif;
    min-height: 100vh;
    padding-bottom: 60px;
    /* subtle star field */
    background-image:
      radial-gradient(1px 1px at 20% 30%, rgba(255,255,255,0.5) 0%, transparent 100%),
      radial-gradient(1px 1px at 40% 70%, rgba(255,255,255,0.4) 0%, transparent 100%),
      radial-gradient(1px 1px at 60% 20%, rgba(255,255,255,0.3) 0%, transparent 100%),
      radial-gradient(1px 1px at 80% 60%, rgba(255,255,255,0.5) 0%, transparent 100%),
      radial-gradient(1px 1px at 90% 10%, rgba(255,255,255,0.3) 0%, transparent 100%),
      radial-gradient(1px 1px at 15% 85%, rgba(255,255,255,0.4) 0%, transparent 100%),
      radial-gradient(1px 1px at 55% 50%, rgba(255,255,255,0.2) 0%, transparent 100%),
      radial-gradient(1px 1px at 70% 90%, rgba(255,255,255,0.4) 0%, transparent 100%);
  }

  /* HEADER */
  header {
    text-align: center;
    padding: 40px 20px 20px;
  }
  .title-row {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 14px;
    margin-bottom: 8px;
  }
  header h1 {
    font-size: 32px;
    font-weight: 900;
    background: linear-gradient(90deg, var(--purple), var(--pink), var(--cyan));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
  }
  header p {
    color: var(--muted);
    font-size: 15px;
    margin-bottom: 20px;
  }

  /* ADOPTION PROGRESS */
  .progress-wrap {
    display: inline-flex;
    align-items: center;
    gap: 12px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 50px;
    padding: 8px 20px;
    font-size: 14px;
    color: var(--muted);
  }
  .progress-wrap strong { color: var(--text); font-size: 16px; }
  .hearts { letter-spacing: 2px; }

  /* GRID */
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(230px, 1fr));
    gap: 20px;
    max-width: 1020px;
    margin: 36px auto 0;
    padding: 0 24px;
  }

  /* CREATURE CARD */
  .card {
    background: var(--surface);
    border: 2px solid var(--border);
    border-radius: 20px;
    padding: 28px 20px 22px;
    text-align: center;
    position: relative;
    transition: transform 0.2s, border-color 0.3s, box-shadow 0.3s;
    overflow: hidden;
    cursor: default;
  }
  .card:hover { transform: translateY(-4px); }
  .card.adopted {
    border-color: var(--accent-color);
    box-shadow: 0 0 24px -4px var(--accent-color);
  }

  /* emoji face */
  .creature-face {
    font-size: 64px;
    display: block;
    margin-bottom: 4px;
    transition: transform 0.15s;
    user-select: none;
    line-height: 1.1;
  }
  .card:hover .creature-face { transform: scale(1.08) rotate(-3deg); }
  .card.adopted .creature-face { animation: wiggle 0.5s ease; }
  @keyframes wiggle {
    0%,100% { transform: rotate(0deg) scale(1); }
    20% { transform: rotate(-8deg) scale(1.15); }
    40% { transform: rotate(8deg) scale(1.15); }
    60% { transform: rotate(-5deg) scale(1.1); }
    80% { transform: rotate(5deg) scale(1.05); }
  }

  .creature-name {
    font-size: 18px;
    font-weight: 800;
    margin-bottom: 4px;
    color: var(--text);
  }
  .creature-tag {
    font-size: 11px;
    letter-spacing: 1px;
    text-transform: uppercase;
    color: var(--accent-color);
    font-weight: 700;
    margin-bottom: 10px;
    display: block;
  }
  .creature-bio {
    font-size: 12.5px;
    color: var(--muted);
    line-height: 1.6;
    margin-bottom: 18px;
    min-height: 40px;
  }

  /* MOOD BAR */
  .mood-row {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-bottom: 16px;
    font-size: 11px;
    color: var(--muted);
  }
  .mood-bar {
    flex: 1;
    height: 6px;
    background: var(--border);
    border-radius: 3px;
    overflow: hidden;
  }
  .mood-fill {
    height: 100%;
    border-radius: 3px;
    background: var(--accent-color);
    transition: width 0.5s ease;
  }

  /* ADOPT BUTTON */
  .adopt-btn {
    width: 100%;
    padding: 10px;
    border-radius: 12px;
    border: 2px solid var(--accent-color);
    background: transparent;
    color: var(--accent-color);
    font-size: 14px;
    font-weight: 700;
    cursor: pointer;
    transition: background 0.2s, color 0.2s, transform 0.1s;
  }
  .adopt-btn:hover {
    background: var(--accent-color);
    color: #0a0a1a;
  }
  .adopt-btn:active { transform: scale(0.96); }
  .card.adopted .adopt-btn {
    background: var(--accent-color);
    color: #0a0a1a;
    cursor: default;
  }

  /* FLOATING HEARTS */
  .floater {
    position: absolute;
    font-size: 20px;
    pointer-events: none;
    animation: float-up 1.2s ease-out forwards;
    bottom: 50px;
  }
  @keyframes float-up {
    0%   { opacity: 1; transform: translateY(0) scale(1); }
    100% { opacity: 0; transform: translateY(-90px) scale(1.4); }
  }

  /* FOOTER */
  footer {
    position: fixed;
    bottom: 0; left: 0; right: 0;
    background: rgba(10,10,26,0.92);
    border-top: 1px solid var(--border);
    padding: 10px 24px;
    font-size: 12px;
    color: var(--muted);
    display: flex;
    gap: 20px;
    backdrop-filter: blur(8px);
  }
  footer .dot { display: inline-block; width: 6px; height: 6px; background: var(--green); border-radius: 50%; margin-right: 5px; }

  /* CONFETTI */
  .confetti-piece {
    position: fixed;
    width: 8px; height: 8px;
    border-radius: 2px;
    pointer-events: none;
    animation: confetti-fall 1.8s ease-in forwards;
  }
  @keyframes confetti-fall {
    0% { opacity: 1; transform: translateY(-10px) rotate(0deg); }
    100% { opacity: 0; transform: translateY(100vh) rotate(720deg); }
  }

  /* ALL ADOPTED BANNER */
  .all-done {
    display: none;
    text-align: center;
    padding: 28px;
    margin: 24px auto;
    max-width: 500px;
    background: linear-gradient(135deg, rgba(176,106,255,0.15), rgba(255,106,176,0.15));
    border: 2px solid var(--purple);
    border-radius: 20px;
    font-size: 22px;
    font-weight: 800;
  }
  .all-done.visible { display: block; }
</style>
</head>
<body>

<header>
  <div class="title-row">
    <span style="font-size:36px">🚀</span>
    <h1>Cosmic Creature Shelter</h1>
    <span style="font-size:36px">✨</span>
  </div>
  <p>Six lonely creatures drifting through the cloud. Can you give them a home?</p>
  <div class="progress-wrap">
    <span class="hearts" id="heart-track"></span>
    <strong><span id="count">0</span> / 6</strong>
    adopted
  </div>
</header>

<div id="all-done-banner" class="all-done">
  🎉 You adopted them all! The cloud is a little less lonely. 🌌
</div>

<div class="grid" id="grid"></div>
<footer id="footer"></footer>

<script>
const CREATURES = [
  {
    id: 1, face: '🐱', name: 'Luna', tag: 'Space Cat',
    bio: 'Meows in binary. Knocks deployments off the shelf at 3am.',
    mood: 82, color: '#b06aff'
  },
  {
    id: 2, face: '🐶', name: 'Bork', tag: 'Cyber Dog',
    bio: 'Borks in JSON. Fetches pull requests. Very good boy.',
    mood: 95, color: '#6af0ff'
  },
  {
    id: 3, face: '🐸', name: 'Glitch', tag: 'Chaos Frog',
    bio: 'Injects faults for fun. Survived every game day. Thriving.',
    mood: 67, color: '#6affa0'
  },
  {
    id: 4, face: '🦊', name: 'Foxy', tag: 'Debug Fox',
    bio: 'Has a sixth sense for race conditions. Smells stack traces.',
    mood: 74, color: '#ffaa6a'
  },
  {
    id: 5, face: '🦄', name: 'Pixel', tag: 'DevOps Unicorn',
    bio: 'Ships to prod on Fridays. Rollbacks are beneath them.',
    mood: 88, color: '#ff6ab0'
  },
  {
    id: 6, face: '🐙', name: 'Octo', tag: 'Cloud Octopus',
    bio: 'Runs 8 microservices simultaneously. Each arm a replica.',
    mood: 91, color: '#ffd700'
  },
];

const adopted = new Set();

function renderAll() {
  document.getElementById('grid').innerHTML = CREATURES.map(c => cardHTML(c)).join('');
  updateProgress();
}

function cardHTML(c) {
  const isAdopted = adopted.has(c.id);
  const hearts = '♥'.repeat(Math.round(c.mood / 20));
  return `
    <div class="card ${isAdopted ? 'adopted' : ''}" id="card-${c.id}" style="--accent-color: ${c.color}">
      <span class="creature-face">${c.face}</span>
      <div class="creature-name">${c.name}</div>
      <span class="creature-tag">${c.tag}</span>
      <p class="creature-bio">${c.bio}</p>
      <div class="mood-row">
        <span>Mood</span>
        <div class="mood-bar"><div class="mood-fill" style="width:${c.mood}%"></div></div>
        <span>${c.mood}%</span>
      </div>
      <button class="adopt-btn" onclick="adopt(${c.id})" ${isAdopted ? 'disabled' : ''}>
        ${isAdopted ? '✓ Adopted!' : 'Adopt ' + c.face}
      </button>
    </div>
  `;
}

function adopt(id) {
  if (adopted.has(id)) return;
  adopted.add(id);

  const card = document.getElementById('card-' + id);
  const c = CREATURES.find(x => x.id === id);
  card.classList.add('adopted');
  card.querySelector('.adopt-btn').textContent = '✓ Adopted!';
  card.querySelector('.adopt-btn').disabled = true;

  spawnHearts(card, c.color);
  updateProgress();

  if (adopted.size === CREATURES.length) {
    setTimeout(() => {
      document.getElementById('all-done-banner').classList.add('visible');
      launchConfetti();
    }, 600);
  }
}

function spawnHearts(card, color) {
  const emojis = ['💖', '✨', '⭐', '💫', '🌟'];
  for (let i = 0; i < 5; i++) {
    setTimeout(() => {
      const el = document.createElement('span');
      el.className = 'floater';
      el.textContent = emojis[i % emojis.length];
      el.style.left = (20 + Math.random() * 60) + '%';
      el.style.animationDelay = (Math.random() * 0.2) + 's';
      card.appendChild(el);
      setTimeout(() => el.remove(), 1400);
    }, i * 80);
  }
}

function launchConfetti() {
  const colors = ['#b06aff','#ff6ab0','#6af0ff','#ffd700','#6affa0','#ffaa6a'];
  for (let i = 0; i < 60; i++) {
    setTimeout(() => {
      const el = document.createElement('div');
      el.className = 'confetti-piece';
      el.style.left = Math.random() * 100 + 'vw';
      el.style.top = '-10px';
      el.style.background = colors[Math.floor(Math.random() * colors.length)];
      el.style.animationDelay = Math.random() * 0.5 + 's';
      document.body.appendChild(el);
      setTimeout(() => el.remove(), 2400);
    }, i * 20);
  }
}

function updateProgress() {
  const n = adopted.size;
  document.getElementById('count').textContent = n;
  document.getElementById('heart-track').textContent = '♥'.repeat(n) + '♡'.repeat(6 - n);
}

async function fetchFooter() {
  try {
    const r = await fetch('/api/status');
    const d = await r.json();
    document.getElementById('footer').innerHTML =
      `<span><span class="dot"></span>Healthy</span>` +
      `<span>Task: ${d.task_id}</span>` +
      `<span>AZ: ${d.az}</span>` +
      `<span>ECS Fargate</span>`;
  } catch (e) {}
}

renderAll();
fetchFooter();
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # noqa: A002
        pass

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"status": "ok"})
        elif self.path == "/api/status":
            meta = _get_task_metadata()
            task_arn = meta.get("TaskARN", "")
            task_id = task_arn.split("/")[-1][:12] if task_arn else socket.gethostname()[:12]
            self._json(200, {
                "task_id": task_id,
                "az": meta.get("AvailabilityZone", "unknown"),
            })
        elif self.path == "/":
            body = HTML.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self._json(404, {"error": "not found"})

    def _json(self, status: int, body) -> None:
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Listening on port {PORT}")
    server.serve_forever()
