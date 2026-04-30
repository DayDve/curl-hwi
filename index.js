addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  const userAgent = request.headers.get('User-Agent') || ''
  
  if (userAgent.includes('curl')) {
    return fetch('https://raw.githubusercontent.com/daydve/curl-hwi/master/hwi.sh')
  }

  return new Response(html, {
    headers: { 'content-type': 'text/html;charset=UTF-8' },
  })
}

const html = `<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>HardWare Inspector</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-color: #0c140c;
            --card-bg: rgba(14, 22, 14, 0.98);
            --accent-color: #00ff41;
            --accent-glow: rgba(0, 255, 65, 0.4);
            --text-main: #ffffff;
            --text-dim: #999999;
            --border-color: #222222;
        }

        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            background-color: var(--bg-color);
            color: var(--text-main);
            font-family: 'Inter', sans-serif;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            overflow: hidden;
            position: relative;
        }

        /* CRT Screen Overlay */
        .crt-bg {
            position: fixed; top: 0; left: 0; width: 100%; height: 100%;
            background: linear-gradient(rgba(0, 0, 0, 0.15) 50%, transparent 50%);
            background-size: 100% 6px;
            z-index: 20;
            pointer-events: none;
        }

        .crt-lines {
            position: fixed; top: 0; left: 0; width: 100%; height: 100%;
            background: linear-gradient(transparent 0%, rgba(0, 255, 65, 0.05) 50%, transparent 100%);
            background-size: 100% 300px;
            animation: scanline 25s linear infinite;
            z-index: 21;
            pointer-events: none;
        }

        @keyframes scanline {
            0% { transform: translateY(-100%); }
            100% { transform: translateY(100%); }
        }

        .vignette {
            position: fixed; top: 0; left: 0; width: 100%; height: 100%;
            background: radial-gradient(circle at center, transparent 0%, rgba(0,0,0,0.1) 60%, rgba(0,0,0,0.5) 100%);
            z-index: 22;
            pointer-events: none;
        }

        .container { max-width: 800px; width: 90%; padding: 2rem; position: relative; z-index: 2; }

        header { margin-bottom: 3.5rem; text-align: center; }
        
        .ascii-logo {
            display: inline-block;
            font-family: 'JetBrains Mono', monospace;
            font-size: clamp(0.35rem, 1.3vw, 0.95rem);
            line-height: 1;
            color: var(--accent-color);
            text-shadow: 0 0 10px var(--accent-glow);
            margin-bottom: 1.2rem;
            white-space: pre;
            text-align: left;
            animation: flicker 5s infinite;
        }

        @keyframes flicker {
            0%, 18%, 22%, 25%, 53%, 57%, 100% { opacity: 1; transform: skew(0deg); }
            20% { opacity: 0.8; transform: skew(0.5deg); }
            55% { opacity: 0.9; transform: skew(-0.5deg); }
        }

        header p { color: var(--text-dim); font-size: 0.85rem; text-transform: uppercase; letter-spacing: 3px; font-weight: 600; }

        .main-card {
            background: var(--card-bg);
            border: 1px solid var(--border-color);
            position: relative;
            padding: 3rem;
            box-shadow: 0 0 40px rgba(0, 0, 0, 0.5);
            backdrop-filter: blur(10px);
        }

        .main-card::before, .main-card::after {
            content: "";
            position: absolute;
            width: 24px; height: 24px;
            border-color: var(--accent-color);
            border-style: solid;
            pointer-events: none;
            opacity: 0.8;
        }

        .main-card::before { top: -1px; left: -1px; border-width: 2px 0 0 2px; }
        .main-card::after { bottom: -1px; right: -1px; border-width: 0 2px 2px 0; }

        .instruction { 
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.85rem; 
            margin-bottom: 1.5rem; 
            color: #bbbbbb;
            text-transform: uppercase;
            letter-spacing: 1px;
            font-weight: 500;
        }

        .cmd-wrapper {
            position: relative;
            background: #000;
            border: 1px solid #1a1a1a;
            padding: 1.2rem 1.5rem;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 1rem;
        }

        .cmd-text {
            font-family: 'JetBrains Mono', monospace;
            font-size: 1.4rem;
            font-weight: 400;
            color: var(--accent-color);
            text-shadow: 0 0 8px rgba(0, 255, 65, 0.3);
            white-space: nowrap;
            overflow-x: auto;
            scrollbar-width: none;
            letter-spacing: -0.5px;
        }

        .cmd-text::-webkit-scrollbar { display: none; }

        .copy-btn {
            background: transparent;
            border: 1px solid var(--accent-color);
            color: var(--accent-color);
            padding: 0.5rem 1rem;
            cursor: pointer;
            transition: all 0.15s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.8rem;
            font-weight: 600;
            text-transform: uppercase;
        }

        .copy-btn:hover { 
            background: var(--accent-color); 
            color: #000; 
            box-shadow: 0 0 15px var(--accent-glow);
        }

        .copy-btn:active {
            transform: scale(0.98);
        }

        .divider {
            height: 1px;
            background: repeating-linear-gradient(90deg, #111, #111 6px, transparent 6px, transparent 12px);
            margin: 2.5rem 0;
        }

        .fallback-title {
            font-family: 'JetBrains Mono', monospace;
            font-size: 0.8rem;
            color: #888;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 1.2rem;
            display: flex;
            align-items: center;
            gap: 1rem;
            font-weight: 500;
        }
        .fallback-title::after { content: ""; flex: 1; height: 1px; background: #222; }
        .fallback-title span { color: #aa4444; border: 1px solid #422; padding: 2px 8px; font-size: 0.75rem; }

        .cmd-wrapper.small { padding: 0.8rem 1.2rem; background: #020202; }
        .cmd-wrapper.small .cmd-text { font-size: 0.95rem; color: #555; text-shadow: none; }

        .toast {
            position: fixed; bottom: 2rem; right: 2rem;
            background: #000; border: 1px solid var(--accent-color);
            color: var(--accent-color); padding: 1rem 1.5rem;
            font-size: 0.85rem; font-family: 'JetBrains Mono', monospace;
            transform: translateY(200%);
            transition: transform 0.3s cubic-bezier(0.68, -0.55, 0.265, 1.55);
            z-index: 1000;
        }
        .toast.show { transform: translateY(0); }

        @media (max-width: 600px) {
            .main-card { padding: 1.5rem; }
            .cmd-text { font-size: 1rem; }
        }
    </style>
</head>
<body>
    <div class="crt-bg"></div>
    <div class="crt-lines"></div>
    <div class="vignette"></div>

    <div class="container">
        <header>
            <div class="ascii-logo">░█░█░█▀█░█▀▄░█▀▄░█░█░█▀█░█▀▄░█▀▀░░░▀█▀░█▀█░█▀▀░█▀█░█▀▀░█▀▀░▀█▀░█▀█░█▀▄
░█▀█░█▀█░█▀▄░█░█░█▄█░█▀█░█▀▄░█▀▀░░░░█░░█░█░▀▀█░█▀▀░█▀▀░█░░░░█░░█░█░█▀▄
░▀░▀░▀░▀░▀░▀░▀▀░░▀░▀░▀░▀░▀░▀░▀▀▀░░░▀▀▀░▀░▀░▀▀▀░▀░░░▀▀▀░▀▀▀░░▀░░▀▀▀░▀░▀</div>
            <p>System Configuration Report Tool</p>
        </header>

        <main class="main-card">
            <p class="instruction">Execute command to generate report</p>
            <div class="cmd-wrapper">
                <div class="cmd-text" id="cmd-main">curl -sL hwi.smbit.pro | bash</div>
                <button class="copy-btn" onclick="copyText('cmd-main', this)">[ COPY ]</button>
            </div>

            <div class="divider"></div>

            <section class="fallback-section">
                <h2 class="fallback-title">Fallback <span>Cloudflare Captcha Bypass</span></h2>
                <div class="cmd-wrapper small">
                    <div class="cmd-text" id="cmd-fallback">curl -sL tinyurl.com/hw-info | bash</div>
                    <button class="copy-btn" onclick="copyText('cmd-fallback', this)">[ COPY ]</button>
                </div>
            </section>
        </main>
    </div>

    <div id="toast" class="toast">> COMMAND COPIED TO CLIPBOARD</div>

    <script>
        function copyText(elementId, btn) {
            const text = document.getElementById(elementId).innerText;
            const originalText = btn.innerText;
            navigator.clipboard.writeText(text).then(() => {
                btn.innerText = '[ DONE ]';
                const toast = document.getElementById('toast');
                toast.classList.add('show');
                setTimeout(() => {
                    toast.classList.remove('show');
                    btn.innerText = originalText;
                }, 2000);
            });
        }
    </script>
</body>
</html>`;
