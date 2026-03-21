import { useState } from "react";

export default function Home() {
  const [script, setScript] = useState("");
  const [ascii, setAscii] = useState(false);
  const [link, setLink] = useState("");

  function obfuscateASCII(code) {
    return code
      .split("")
      .map(c => "\\" + c.charCodeAt(0))
      .join("");
  }

  function generate() {
    let finalScript = script;

    if (ascii) {
      finalScript = `loadstring("${obfuscateASCII(script)}")()`;
    }

    const id = btoa(finalScript);
    const url = `${window.location.origin}/script?id=${id}`;

    setLink(url);
  }

  return (
    <div style={{ padding: 20, fontFamily: "Arial" }}>
      <h1>🔥 Script Protector</h1>

      <textarea
        placeholder="Cole seu script aqui..."
        value={script}
        onChange={(e) => setScript(e.target.value)}
        style={{ width: "100%", height: 200 }}
      />

      <br /><br />

      <label>
        <input
          type="checkbox"
          checked={ascii}
          onChange={(e) => setAscii(e.target.checked)}
        />
        ASCII Obfuscation (easy to skid)
      </label>

      <br /><br />

      <button onClick={generate}>🔒 Proteger Script</button>

      {link && (
        <div>
          <p>🔗 Link:</p>
          <input value={link} readOnly style={{ width: "100%" }} />
        </div>
      )}
    </div>
  );
}
