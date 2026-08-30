"use client";

import { useState } from "react";
import {
  BatteryMedium,
  ChevronLeft,
  ChevronRight,
  Grid2X2,
  Link2,
  LockKeyhole,
  Moon,
  Pin,
  Search,
  SlidersHorizontal,
  Sun,
  Wifi,
} from "lucide-react";
import styles from "./IOSDesignDirectionsStudy.module.css";

type Palette = "light" | "dark";
type Surface = "log" | "reader";
type DirectionId = "paperTape" | "fieldLog" | "ledger" | "indexTape";

const directions: Array<{
  id: DirectionId;
  agent: string;
  name: string;
  thesis: string;
  signature: string[];
  scoutRef: string;
}> = [
  {
    id: "paperTape",
    agent: "Opus",
    name: "Paper Tape",
    thesis:
      "Human ink on paper; machine knowledge on one continuous graphite rail.",
    signature: [
      "44 pt time rail",
      "workspace as title",
      "sync reduced to a rule",
    ],
    scoutRef: "ref:f-5c5sbf",
  },
  {
    id: "fieldLog",
    agent: "Grok",
    name: "Field Log",
    thesis:
      "A warm pocket instrument: status, scope, paper bands, then search at the thumb.",
    signature: [
      "paper-band rows",
      "trust capsule",
      "floating search dock",
    ],
    scoutRef: "ref:z-a8x57g",
  },
  {
    id: "ledger",
    agent: "Kimi",
    name: "Ledger",
    thesis:
      "The macOS popover made native: numbered rows, square state, sharp ruled geometry.",
    signature: [
      "numbered entries",
      "square sync pip",
      "zero-radius rules",
    ],
    scoutRef: "ref:0-4qjlsi",
  },
  {
    id: "indexTape",
    agent: "Grok",
    name: "Index Tape",
    thesis:
      "Chronology is the structure; ledger is the discipline — one carbon tape, machine-indexed and sharp-ruled.",
    signature: [
      "indexed machine rail",
      "sync rule + square",
      "zero-radius carbon geometry",
    ],
    scoutRef: "ref:r-p0f0u9",
  },
];

const notes = [
  {
    title: "Launch checklist",
    excerpt:
      "Verify the encrypted LAN handshake — read notes after the Mac disconnects.",
    meta: "launch · #release",
    time: "14:22",
    relative: "2h",
    index: "01",
    pinned: true,
  },
  {
    title: "Pairing notes",
    excerpt:
      "Each snapshot payload is sealed end to end inside the encrypted peer session.",
    meta: "hudson · #security",
    time: "MON",
    relative: "1d",
    index: "02",
    pinned: false,
  },
  {
    title: "Design review",
    excerpt:
      "Keep note recall calm, direct, and recognizably connected to the desktop.",
    meta: "blink · #ios",
    time: "4 AUG",
    relative: "3d",
    index: "03",
    pinned: false,
  },
];

export function IOSDesignDirectionsStudy() {
  const [palette, setPalette] = useState<Palette>("light");
  const [surface, setSurface] = useState<Surface>("log");

  return (
    <div className={styles.study}>
      <header className={styles.controlBar}>
        <div>
          <p className={styles.controlKicker}>Controlled comparison</p>
          <p className={styles.controlCopy}>
            Same notes, state, frame, and product behavior. Only the visual
            system changes.
          </p>
        </div>

        <div className={styles.controls} aria-label="Study controls">
          <div className={styles.segmented} aria-label="Surface">
            <button
              type="button"
              aria-pressed={surface === "log"}
              onClick={() => setSurface("log")}
            >
              Log
            </button>
            <button
              type="button"
              aria-pressed={surface === "reader"}
              onClick={() => setSurface("reader")}
            >
              Reader
            </button>
          </div>

          <div className={styles.segmented} aria-label="Palette">
            <button
              type="button"
              aria-label="Light palette"
              aria-pressed={palette === "light"}
              onClick={() => setPalette("light")}
            >
              <Sun size={14} aria-hidden="true" />
              Light
            </button>
            <button
              type="button"
              aria-label="Dark palette"
              aria-pressed={palette === "dark"}
              onClick={() => setPalette("dark")}
            >
              <Moon size={14} aria-hidden="true" />
              Dark
            </button>
          </div>
        </div>
      </header>

      <div className={styles.matrix}>
        {directions.map((direction) => (
          <article className={styles.direction} key={direction.id}>
            <header className={styles.directionHeader}>
              <div className={styles.agentLine}>
                <span>{direction.agent}</span>
                <span aria-hidden="true">/</span>
                <span>{direction.scoutRef}</span>
              </div>
              <h3>{direction.name}</h3>
              <p>{direction.thesis}</p>
            </header>

            <PhoneShell
              direction={direction.id}
              palette={palette}
              surface={surface}
              label={`${direction.agent} — ${direction.name}, ${palette} ${surface}`}
            />

            <ul className={styles.signature} aria-label="Direction signatures">
              {direction.signature.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
          </article>
        ))}
      </div>

      <section className={styles.comparisonLedger} aria-labelledby="comparison-ledger">
        <div className={styles.ledgerIntro}>
          <p className={styles.controlKicker}>Design disposition</p>
          <h3 id="comparison-ledger">What each direction is arguing for</h3>
          <p>
            These are alternatives, not a vote. Index Tape is an intentional
            merge of Paper Tape and Ledger under one thesis — not a bag of both.
          </p>
        </div>
        <div className={styles.ledgerRows}>
          <ComparisonRow
            label="Projected density"
            values={["≈6 rows", "≈4 paper bands", "≈5 ruled entries", "≈6 indexed rows"]}
          />
          <ComparisonRow
            label="Search"
            values={[
              "bottom tape dock",
              "floating thumb dock",
              "native top field",
              "sharp bottom index field",
            ]}
          />
          <ComparisonRow
            label="Offline"
            values={[
              "neutral success",
              "amber retained copy",
              "amber state pip",
              "neutral + square pip",
            ]}
          />
          <ComparisonRow
            label="Dark world"
            values={[
              "neutral graphite",
              "botanical graphite",
              "neutral graphite",
              "neutral graphite",
            ]}
          />
          <ComparisonRow
            label="iPad"
            values={[
              "tape + floating sheet",
              "paper split view",
              "flat ruled split",
              "indexed tape + flat reader",
            ]}
          />
          <ComparisonRow
            label="Machine gutter"
            values={[
              "time + pin rail",
              "none (meta in plate)",
              "numbered index column",
              "index over stamp + pin",
            ]}
          />
        </div>
      </section>
    </div>
  );
}

function ComparisonRow({ label, values }: { label: string; values: string[] }) {
  return (
    <div className={styles.comparisonRow}>
      <strong>{label}</strong>
      {values.map((value, index) => (
        <span key={`${label}-${directions[index].id}`}>{value}</span>
      ))}
    </div>
  );
}

function PhoneShell({
  direction,
  palette,
  surface,
  label,
}: {
  direction: DirectionId;
  palette: Palette;
  surface: Surface;
  label: string;
}) {
  return (
    <div
      className={`${styles.phone} ${styles[direction]}`}
      data-palette={palette}
      role="img"
      aria-label={label}
    >
      <div className={styles.phoneScreen}>
        <StatusBar />
        {surface === "log" ? (
          <LogScreen direction={direction} />
        ) : (
          <ReaderScreen direction={direction} />
        )}
        <div className={styles.homeIndicator} />
      </div>
    </div>
  );
}

function StatusBar() {
  return (
    <div className={styles.statusBar} aria-hidden="true">
      <span>9:41</span>
      <span className={styles.dynamicIsland} />
      <span className={styles.statusIcons}>
        <Wifi size={11} strokeWidth={2.4} />
        <BatteryMedium size={14} strokeWidth={2.2} />
      </span>
    </div>
  );
}

function BlinkMark({ compact = false }: { compact?: boolean }) {
  return (
    <span className={compact ? styles.markCompact : styles.mark} aria-hidden="true">
      <span />
      <span />
    </span>
  );
}

function LogScreen({ direction }: { direction: DirectionId }) {
  if (direction === "paperTape") return <PaperTapeLog />;
  if (direction === "fieldLog") return <FieldLog />;
  if (direction === "ledger") return <LedgerLog />;
  return <IndexTapeLog />;
}

function PaperTapeLog() {
  return (
    <div className={styles.logScreen}>
      <div className={styles.tapeToolbar}>
        <span className={styles.iconWell}><BlinkMark compact /></span>
        <span className={styles.toolbarGlyph}><Grid2X2 size={15} /></span>
        <span className={styles.toolbarGlyph}><Link2 size={15} /></span>
      </div>
      <div className={styles.tapeTitle}>Launch</div>
      <div className={styles.tapeStatusRule} />
      <div className={styles.tapeStatus}>OFFLINE COPY · UPDATED 2H AGO</div>
      <div className={styles.tapeSection}>
        <span><b>LOG</b> / LAUNCH</span>
        <span>3 REC</span>
      </div>
      <div className={styles.tapeList}>
        {notes.map((note) => (
          <div className={styles.tapeRow} key={note.title}>
            <div className={styles.tapeRail}>
              <span>{note.time}</span>
              {note.pinned ? <i /> : null}
            </div>
            <NotePlate note={note} />
          </div>
        ))}
      </div>
      <div className={styles.tapeSearch}>
        <Search size={14} />
        <span>SEARCH · LAUNCH</span>
      </div>
    </div>
  );
}

function FieldLog() {
  return (
    <div className={styles.logScreen}>
      <div className={styles.fieldToolbar}>
        <span className={styles.workspaceButton}><Grid2X2 size={14} /></span>
        <span className={styles.toolbarGlyph}><SlidersHorizontal size={15} /></span>
        <span className={styles.toolbarGlyph}><Link2 size={15} /></span>
      </div>
      <div className={styles.fieldTitle}>blink</div>
      <div className={styles.syncCapsule}>
        <span className={styles.syncIcon}><LockKeyhole size={15} /></span>
        <span>
          <b>Available offline</b>
          <small>Updated 2 hours ago</small>
        </span>
        <i />
      </div>
      <div className={styles.fieldSection}>
        <span><b>LOG</b> / LAUNCH</span>
        <span>3 REC</span>
      </div>
      <div className={styles.fieldRows}>
        {notes.map((note) => (
          <div className={styles.fieldRow} key={note.title}>
            <div className={styles.rowTitleLine}>
              <span>{note.pinned ? <Pin size={10} fill="currentColor" /> : null}{note.title}</span>
              <time>{note.relative}</time>
            </div>
            <p>{note.excerpt}</p>
            <div className={styles.rowMeta}>{note.meta}</div>
            <ChevronRight className={styles.rowChevron} size={13} />
          </div>
        ))}
      </div>
      <div className={styles.fieldSearch}>
        <Search size={14} />
        <span>Search notes</span>
      </div>
    </div>
  );
}

function LedgerLog() {
  return (
    <div className={styles.logScreen}>
      <div className={styles.ledgerToolbar}>
        <span className={styles.toolbarGlyph}><Grid2X2 size={15} /></span>
        <span className={styles.toolbarGlyph}><Link2 size={15} /></span>
      </div>
      <div className={styles.ledgerTitle}>blink</div>
      <div className={styles.ledgerSearch}>
        <Search size={14} />
        <span>Search notes</span>
      </div>
      <div className={styles.syncStrip}>
        <i />
        <span>
          <b>Available offline</b>
          <small>UPDATED 2H AGO</small>
        </span>
      </div>
      <div className={styles.ledgerSection}>
        <span><b>LOG</b> / LAUNCH</span>
        <span>3 REC</span>
      </div>
      <div className={styles.ledgerList}>
        {notes.map((note, index) => (
          <div
            className={`${styles.ledgerRow} ${index === 0 ? styles.ledgerSelected : ""}`}
            key={note.title}
          >
            <span className={styles.ledgerIndex}>
              {note.pinned ? <Pin size={10} fill="currentColor" /> : note.index}
            </span>
            <NotePlate note={note} relative />
          </div>
        ))}
      </div>
    </div>
  );
}

function IndexTapeLog() {
  return (
    <div className={styles.logScreen}>
      <div className={styles.indexToolbar}>
        <span className={styles.iconWell}>
          <BlinkMark compact />
        </span>
        <span className={styles.toolbarGlyph}>
          <Link2 size={15} />
        </span>
      </div>
      <div className={styles.indexTitle}>Launch</div>
      <div className={styles.indexStatusRule} />
      <div className={styles.indexStatus}>
        <i />
        <span>OFFLINE COPY · UPDATED 2H AGO</span>
      </div>
      <div className={styles.indexSection}>
        <span>
          <b>LOG</b> / LAUNCH
        </span>
        <span>3 REC</span>
      </div>
      <div className={styles.indexList}>
        {notes.map((note, index) => (
          <div
            className={`${styles.indexRow} ${index === 0 ? styles.indexSelected : ""}`}
            key={note.title}
          >
            <div className={styles.indexRail}>
              {note.pinned ? (
                <i className={styles.indexPin} />
              ) : (
                <span className={styles.indexNum}>{note.index}</span>
              )}
              <span className={styles.indexStamp}>{note.time}</span>
            </div>
            <NotePlate note={note} />
          </div>
        ))}
      </div>
      <div className={styles.indexSearch}>
        <Search size={13} />
        <span>SEARCH · LAUNCH</span>
      </div>
    </div>
  );
}

function NotePlate({
  note,
  relative = false,
}: {
  note: (typeof notes)[number];
  relative?: boolean;
}) {
  return (
    <div className={styles.notePlate}>
      <div className={styles.notePlateTitle}>
        <span>{note.title}</span>
        {relative ? <time>{note.relative}</time> : null}
      </div>
      <p>{note.excerpt}</p>
      <div className={styles.notePlateMeta}>{note.meta}</div>
    </div>
  );
}

function ReaderScreen({ direction }: { direction: DirectionId }) {
  return (
    <div className={`${styles.readerScreen} ${styles[`${direction}Reader`]}`}>
      <div className={styles.readerToolbar}>
        <ChevronLeft size={18} />
        <span>Notes</span>
        <Link2 size={15} />
      </div>
      {direction === "paperTape" ? (
        <div className={styles.readerRail} aria-hidden="true">
          <span>14:22</span>
          <i />
          <span>MON</span>
        </div>
      ) : null}
      {direction === "ledger" ? (
        <div className={styles.readerRuleIndex} aria-hidden="true">
          <span>01</span>
          <span>02</span>
          <span>03</span>
        </div>
      ) : null}
      {direction === "indexTape" ? (
        <div className={styles.indexReaderGutter} aria-hidden="true">
          <span>01</span>
          <small>14:22</small>
        </div>
      ) : null}
      <article className={styles.readerBody}>
        <div className={styles.readerKicker}>
          <BlinkMark compact />
          <span>MARKDOWN / READ ONLY</span>
        </div>
        <h4>Launch checklist</h4>
        <div className={styles.readerMeta}>AUG 1, 2026 · 17:20 · LAUNCH</div>
        <hr />
        <p>
          Verify the encrypted LAN handshake, then read these notes after the
          Mac disconnects. The durable truth stays in the Markdown file.
        </p>
        <h5>Offline first</h5>
        <ul>
          <li>The last good snapshot remains readable.</li>
          <li>Unknown frontmatter survives every round trip.</li>
          <li>The companion never edits the source note.</li>
        </ul>
        <blockquote>Capture on the desk. Recall from anywhere nearby.</blockquote>
        <div className={styles.readerTags}>
          <span>#release</span>
          <span>#ios</span>
        </div>
      </article>
    </div>
  );
}
