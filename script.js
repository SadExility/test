export default function handler(req, res) {
  const { id } = req.query;

  if (!id) {
    return res.send("Erro");
  }

  const script = Buffer.from(id, "base64").toString("utf-8");

  const ua = req.headers["user-agent"] || "";

  // 🔥 Detecta navegador vs executor
  const isBrowser =
    ua.includes("Mozilla") ||
    ua.includes("Chrome") ||
    ua.includes("Safari");

  if (isBrowser) {
    return res.send(`
      <html>
        <h1>🔒 Script Protegido</h1>
        <p>Você não tem permissão.</p>
      </html>
    `);
  }

  // 👇 executor recebe o script
  res.setHeader("Content-Type", "text/plain");
  return res.send(script);
}
