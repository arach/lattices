import type { ReactNode } from "react";

interface EngMarkdownProps {
  body: string;
  fromSlug?: string;
  buildFileHref: (path: string, fromSlug?: string) => string;
}

type InlineToken = string | ReactNode;

function slugify(input: string): string {
  return input
    .toLowerCase()
    .replace(/`([^`]+)`/g, "$1")
    .replace(/[^\w\s-]/g, "")
    .trim()
    .replace(/\s+/g, "-");
}

function inline(text: string, buildFileHref: EngMarkdownProps["buildFileHref"], fromSlug?: string): InlineToken[] {
  const out: InlineToken[] = [];
  const pattern = /(`[^`]+`|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\))/g;
  let last = 0;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(text))) {
    if (match.index > last) out.push(text.slice(last, match.index));
    const token = match[0];
    const key = `${match.index}-${token}`;
    if (token.startsWith("`")) {
      out.push(<code key={key}>{token.slice(1, -1)}</code>);
    } else if (token.startsWith("**")) {
      out.push(<strong key={key}>{inline(token.slice(2, -2), buildFileHref, fromSlug)}</strong>);
    } else {
      const link = token.match(/^\[([^\]]+)\]\(([^)]+)\)$/);
      if (link) {
        const href = link[2].startsWith("http") || link[2].startsWith("#")
          ? link[2]
          : buildFileHref(link[2], fromSlug);
        out.push(
          <a key={key} href={href} target={href.startsWith("http") ? "_blank" : undefined} rel="noopener noreferrer">
            {inline(link[1], buildFileHref, fromSlug)}
          </a>,
        );
      } else {
        out.push(token);
      }
    }
    last = pattern.lastIndex;
  }
  if (last < text.length) out.push(text.slice(last));
  return out;
}

function renderTable(lines: string[], key: number, buildFileHref: EngMarkdownProps["buildFileHref"], fromSlug?: string) {
  const rows = lines.map((line) => line.trim().replace(/^\||\|$/g, "").split("|").map((cell) => cell.trim()));
  const [head, , ...body] = rows;
  return (
    <div className="eng-table-wrap" key={key}>
      <table>
        <thead>
          <tr>{head.map((cell, i) => <th key={i}>{inline(cell, buildFileHref, fromSlug)}</th>)}</tr>
        </thead>
        <tbody>
          {body.map((row, rowIndex) => (
            <tr key={rowIndex}>
              {row.map((cell, cellIndex) => <td key={cellIndex}>{inline(cell, buildFileHref, fromSlug)}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function EngMarkdown({ body, fromSlug, buildFileHref }: EngMarkdownProps) {
  const lines = body.replace(/\r\n/g, "\n").split("\n");
  const blocks: ReactNode[] = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];
    const trimmed = line.trim();
    if (!trimmed) {
      i += 1;
      continue;
    }

    if (trimmed.startsWith("```")) {
      const lang = trimmed.slice(3).trim();
      const code: string[] = [];
      i += 1;
      while (i < lines.length && !lines[i].trim().startsWith("```")) {
        code.push(lines[i]);
        i += 1;
      }
      if (i < lines.length) i += 1;
      blocks.push(
        <div className="eng-codeblock" key={blocks.length}>
          <div className="eng-codeblock__strip">
            <span className="eng-codeblock__dot" />
            <span className="eng-codeblock__dot" />
            <span className="eng-codeblock__dot" />
            {lang ? <span className="eng-codeblock__lang">{lang}</span> : null}
          </div>
          <pre><code>{code.join("\n")}</code></pre>
        </div>,
      );
      continue;
    }

    const heading = trimmed.match(/^(#{1,4})\s+(.+)$/);
    if (heading) {
      const level = heading[1].length;
      const text = heading[2].replace(/\s+#+$/, "");
      const id = slugify(text);
      const children = inline(text, buildFileHref, fromSlug);
      if (level === 1) blocks.push(<h1 id={id} key={blocks.length}>{children}</h1>);
      else if (level === 2) blocks.push(<h2 id={id} key={blocks.length}>{children}</h2>);
      else if (level === 3) blocks.push(<h3 id={id} key={blocks.length}>{children}</h3>);
      else blocks.push(<h4 id={id} key={blocks.length}>{children}</h4>);
      i += 1;
      continue;
    }

    if (/^(-{3,}|\* \* \*)$/.test(trimmed)) {
      blocks.push(<hr key={blocks.length} />);
      i += 1;
      continue;
    }

    if (trimmed.startsWith(">")) {
      const quote: string[] = [];
      while (i < lines.length && lines[i].trim().startsWith(">")) {
        quote.push(lines[i].trim().replace(/^>\s?/, ""));
        i += 1;
      }
      blocks.push(<blockquote key={blocks.length}><p>{inline(quote.join(" "), buildFileHref, fromSlug)}</p></blockquote>);
      continue;
    }

    if (/^[-*+]\s+/.test(trimmed)) {
      const items: string[] = [];
      while (i < lines.length && /^[-*+]\s+/.test(lines[i].trim())) {
        items.push(lines[i].trim().replace(/^[-*+]\s+/, ""));
        i += 1;
      }
      blocks.push(<ul key={blocks.length}>{items.map((item, idx) => <li key={idx}>{inline(item, buildFileHref, fromSlug)}</li>)}</ul>);
      continue;
    }

    if (/^\d+\.\s+/.test(trimmed)) {
      const items: string[] = [];
      while (i < lines.length && /^\d+\.\s+/.test(lines[i].trim())) {
        items.push(lines[i].trim().replace(/^\d+\.\s+/, ""));
        i += 1;
      }
      blocks.push(<ol key={blocks.length}>{items.map((item, idx) => <li key={idx}>{inline(item, buildFileHref, fromSlug)}</li>)}</ol>);
      continue;
    }

    if (trimmed.startsWith("|") && i + 1 < lines.length && /^\s*\|?[\s:-]+\|/.test(lines[i + 1])) {
      const table: string[] = [line, lines[i + 1]];
      i += 2;
      while (i < lines.length && lines[i].trim().startsWith("|")) {
        table.push(lines[i]);
        i += 1;
      }
      blocks.push(renderTable(table, blocks.length, buildFileHref, fromSlug));
      continue;
    }

    const para: string[] = [trimmed];
    i += 1;
    while (i < lines.length && lines[i].trim() && !/^(#{1,4}\s|```|>|[-*+]\s+|\d+\.\s+|\|)/.test(lines[i].trim())) {
      para.push(lines[i].trim());
      i += 1;
    }
    blocks.push(<p key={blocks.length}>{inline(para.join(" "), buildFileHref, fromSlug)}</p>);
  }

  return <div className="eng-doc">{blocks}</div>;
}
