export default {
  async fetch(request) {
    const ua = request.headers.get("User-Agent") || "";
    const GITHUB_URL = "https://raw.githubusercontent.com/DayDve/curl-hwi/refs/heads/master/hwi.sh";

    if (ua.startsWith("curl") || ua.startsWith("HWI")) {
      const githubResponse = await fetch(GITHUB_URL);

      if (!githubResponse.ok) {
        return new Response("Failed to fetch script from GitHub\n", { status: 502 });
      }

      const script = await githubResponse.text();

      return new Response(script, { 
        headers: { "Content-Type": "text/plain; charset=utf-8" } 
      });
    }
    
    const html = `<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>HardWare Inspector</title>
    <style>
        body { background-color: #0f0f0f; color: #00ff00; font-family: "Courier New", Courier, monospace; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; margin: 0; text-align: center; }
        h1 { font-size: 2rem; font-weight: normal; margin-bottom: 1.5rem; }
        p { font-size: 1.2rem; margin-bottom: 1.5rem; }
        .cmd-box { border: 1px solid #555; border-radius: 8px; padding: 1.5rem 2.5rem; font-size: 1.5rem; background-color: #000; margin-bottom: 2rem; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3); }
        .fallback { margin-top: 2rem; color: #888; }
        .fallback p { font-size: 1rem; margin-bottom: 1rem; }
        .fallback .cmd-box { font-size: 1.2rem; padding: 1rem 2rem; border-color: #333; color: #00cc00; margin-bottom: 0; }
    </style>
</head>
<body>
    <h1>HardWare Inspector (report generator)</h1>
    <p>Для получения сводного отчета выполните команду:</p>
    <div class="cmd-box">curl -A "HWI" -s https://hwi.smbit.pro | bash</div>
    
    <div class="fallback">
        <p>Fallback URL:</p>
        <div class="cmd-box">curl -sL https://tinyurl.com/hw-info | bash</div>
    </div>
</body>
</html>`;

    return new Response(html, { 
      status: 200, 
      headers: { "Content-Type": "text/html; charset=utf-8" } 
    });
  }
};
