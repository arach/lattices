import type { ActionMessage, ActionResponse } from "./messages.js";

declare const chrome: {
  runtime: {
    lastError?: { message?: string };
    sendMessage: (
      message: ActionMessage,
      callback: (response?: ActionResponse) => void
    ) => void;
  };
};

type BridgeRequest = {
  id: string;
  message: ActionMessage;
};

const bridgeURL = "ws://127.0.0.1:4321/chrome-companion";
const statusElement = document.getElementById("status");
let socket: WebSocket | null = null;
let reconnectTimer: ReturnType<typeof setTimeout> | undefined;

connect();

function connect() {
  if (socket && socket.readyState <= WebSocket.OPEN) {
    return;
  }

  setStatus("connecting");
  socket = new WebSocket(bridgeURL);
  socket.addEventListener("open", () => {
    setStatus("connected");
    socket?.send(JSON.stringify({ type: "hello", name: "Action Chrome Companion Bridge Page" }));
  });
  socket.addEventListener("message", (event) => {
    void handleBridgeMessage(event.data);
  });
  socket.addEventListener("close", scheduleReconnect);
  socket.addEventListener("error", scheduleReconnect);
}

function scheduleReconnect() {
  socket = null;
  setStatus("waiting");
  if (reconnectTimer !== undefined) {
    return;
  }

  reconnectTimer = setTimeout(() => {
    reconnectTimer = undefined;
    connect();
  }, 1000);
}

async function handleBridgeMessage(data: unknown) {
  let request: BridgeRequest;
  try {
    request = JSON.parse(String(data)) as BridgeRequest;
  } catch {
    return;
  }

  const response = await dispatchToExtension(request.message)
    .catch((error) => ({ ok: false as const, error: errorMessage(error) }));
  socket?.send(JSON.stringify({ id: request.id, response }));
}

function dispatchToExtension(message: ActionMessage): Promise<ActionResponse> {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage(message, (response?: ActionResponse) => {
      const error = chrome.runtime.lastError;
      if (error) {
        resolve({ ok: false, error: error.message ?? "No extension response." });
        return;
      }
      resolve(response ?? { ok: false, error: "No extension response." });
    });
  });
}

function setStatus(status: string) {
  if (statusElement) {
    statusElement.textContent = status;
  }
  document.body.dataset.status = status;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
