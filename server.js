const express = require("express");
const app = express();

app.use(express.static(__dirname));

app.get("/script", (req, res) => {
  const id = req.query.id;
  if (!id) return res.send("Erro");

  const script = Buffer.from(id, "base64").toString("utf-8");

  const ua = req.headers["user-agent"] || "";

  const isBrowser =
    ua.includes("Mozilla") ||
    ua.includes("Chrome");

  if (isBrowser) {
    return res.send(`
      <h1>🔒 Script Protegido</h1>
      <p>Você não tem permissão</p>
    `);
  }

  res.setHeader("Content-Type", "text/plain");
  res.send(script);
});

app.listen(3000, () => console.log("Rodando na porta 3000"));
