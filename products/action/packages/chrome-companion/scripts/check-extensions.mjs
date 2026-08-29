#!/usr/bin/env bun

const port = Number(process.env.ACTION_CHROME_COMPANION_DEBUG_PORT || 9333);
const pages = await fetch(`http://127.0.0.1:${port}/json`).then((r) => r.json());
const page = pages.find((entry) => entry.url?.startsWith("chrome://extensions"));
if (!page) {
  console.log("no extensions page");
  process.exit(1);
}

const ws = new WebSocket(page.webSocketDebuggerUrl);
let id = 1;
const pending = new Map();
ws.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    message.error ? reject(new Error(JSON.stringify(message.error))) : resolve(message.result);
  }
});
await new Promise((resolve, reject) => {
  ws.addEventListener("open", resolve, { once: true });
  ws.addEventListener("error", reject, { once: true });
});
const call = (method, params = {}) => new Promise((resolve, reject) => {
  const messageId = id++;
  pending.set(messageId, { resolve, reject });
  ws.send(JSON.stringify({ id: messageId, method, params }));
});

const result = await call("Runtime.evaluate", {
  expression: `(() => {
    const items = [...document.querySelector("extensions-manager")?.shadowRoot
      ?.querySelector("extensions-item-list")?.shadowRoot
      ?.querySelectorAll("extensions-item") || []];
    return items.map((el) => ({
      name: el.shadowRoot?.querySelector("#name")?.textContent?.trim(),
      id: el.id,
    }));
  })()`,
  returnByValue: true,
});

console.log(JSON.stringify(result.result?.value ?? [], null, 2));
ws.close();