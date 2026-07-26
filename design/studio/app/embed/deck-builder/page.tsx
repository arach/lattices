"use client";

/**
 * Chrome-free deck builder for embedding in the Mac app's WKWebView.
 *
 * Bridge contract (JS ↔ Swift):
 *  - Init — the host injects `window.__DECK_INIT__` (Deck[]) before the page
 *    loads (a WKUserScript at documentStart), or posts a
 *    `{ type: "deck-init", decks }` window message afterwards.
 *  - Save — every layout change is posted to the host via
 *    `window.webkit.messageHandlers.deck.postMessage({ type: "deck-change", decks })`.
 *    In a plain browser (no bridge) it logs to the console instead, so the
 *    contract is fully testable without the Mac.
 */

import { useEffect, useState } from "react";
import { DeckBuilder, type Deck } from "@/studio/studies/DeckBuilder";

declare global {
  interface Window {
    __DECK_INIT__?: Deck[];
    webkit?: { messageHandlers?: Record<string, { postMessage: (msg: unknown) => void }> };
  }
}

export default function DeckBuilderEmbed() {
  const [initial, setInitial] = useState<Deck[] | undefined>(undefined);
  const [ver, setVer] = useState(0); // bump → remount DeckBuilder with fresh initialDecks
  const [ready, setReady] = useState(false);

  useEffect(() => {
    if (typeof window !== "undefined" && Array.isArray(window.__DECK_INIT__)) {
      setInitial(window.__DECK_INIT__);
      setVer((v) => v + 1);
    }
    const onMsg = (e: MessageEvent) => {
      const d = e.data as { type?: string; decks?: Deck[] } | null;
      if (d && d.type === "deck-init" && Array.isArray(d.decks)) {
        setInitial(d.decks);
        setVer((v) => v + 1);
      }
    };
    window.addEventListener("message", onMsg);
    setReady(true);
    return () => window.removeEventListener("message", onMsg);
  }, []);

  const onChange = (decks: Deck[]) => {
    const bridge = typeof window !== "undefined" ? window.webkit?.messageHandlers?.deck : undefined;
    if (bridge) bridge.postMessage({ type: "deck-change", decks });
    else console.log("[deck-change]", JSON.stringify(decks));
  };

  if (!ready) return null;

  return (
    <div style={{ minHeight: "100vh", background: "#060607", color: "#e2e2df" }}>
      <DeckBuilder key={ver} initialDecks={initial} onChange={onChange} className="p-6" />
    </div>
  );
}
