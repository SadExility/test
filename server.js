const express = require("express");
const fs = require("fs");

const app = express();
const PORT = 3000;

let db = {};

if (fs.existsSync("users.json")) {
  db = JSON.parse(fs.readFileSync("users.json"));
}

// rota de unlock
app.get("/unlock", (req, res) => {
  const hwid = req.query.hwid;

  if (!hwid) {
    return res.json({ message: "HWID inválido" });
  }

  db[hwid] = {
    unlocked: true,
    time: Date.now()
  };

  fs.writeFileSync("users.json", JSON.stringify(db, null, 2));

  res.json({ message: "Script liberado com sucesso!" });
});

// rota de verificação
app.get("/check", (req, res) => {
  const hwid = req.query.hwid;

  if (db[hwid] && db[hwid].unlocked) {
    return res.send("true");
  }

  res.send("false");
});

app.listen(PORT, () => {
  console.log("Rodando em http://localhost:" + PORT);
});
