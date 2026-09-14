import { useId, type SVGProps } from 'react';

export interface ActionPalette {
  paper: string;
  ink: string;
  cursor: string;
  guide: string;
  grid: string;
}

export interface ActionMarkProps extends Omit<SVGProps<SVGSVGElement>, 'children' | 'name'> {
  theme?: 'light' | 'dark';
  /** Show the architectural construction layer. Defaults to true. */
  guides?: boolean;
  /** These layers default to the guides setting, but can be controlled separately. */
  grid?: boolean;
  annotations?: boolean;
  titleBlock?: boolean;
  background?: boolean;
  /** Extra SVG units of paper around the approved 720 × 640 drawing. */
  padding?: number;
  palette?: Partial<ActionPalette>;
  label?: string;
  decorative?: boolean;
  figure?: string;
  name?: string;
  organization?: string;
  year?: number;
  revision?: string;
}

/** Action construction with equal perpendicular edge widths. Geometry is fixed; presentation is configurable. */
export function ActionMark({
  theme = 'light', guides = true, grid = guides, annotations = guides,
  titleBlock = guides, background = true, padding = 0, palette,
  label = 'Action logo', decorative = false,
  figure = 'FIG. A', name = 'ACTION', organization = 'LATTICES',
  year = 2026, revision = 'STUDY 02', style, ...svgProps
}: ActionMarkProps) {
  const id = useId();
  const gridId = `${id}-grid`;
  const gapId = `${id}-gap`;
  const titleId = `${id}-title`;
  const inset = Number.isFinite(padding) ? Math.max(0, padding) : 0;
  const colors: ActionPalette = {
    paper: theme === 'dark' ? '#19282a' : '#f4efe6',
    ink: theme === 'dark' ? '#f4efe6' : '#19282a',
    cursor: '#c58a70', guide: theme === 'dark' ? '#819d96' : '#71908d',
    grid: '#367b7c', ...palette,
  };
  return (
    <svg xmlns="http://www.w3.org/2000/svg"
      viewBox={`${-inset} ${-inset} ${720 + inset * 2} ${640 + inset * 2}`}
      style={{ display: 'block', width: '100%', height: 'auto', ...style }}
      {...svgProps}
      role={decorative ? undefined : 'img'}
      aria-hidden={decorative || undefined}
      aria-labelledby={decorative ? undefined : titleId}
    >
      {!decorative && <title id={titleId}>{label}</title>}
      {background && <rect x={-inset} y={-inset} width={720 + inset * 2} height={640 + inset * 2} fill={colors.paper} />}
      <defs>
        <pattern id={gridId} width="20" height="20" patternUnits="userSpaceOnUse">
          <path d="M20 0H0V20" fill="none" stroke={colors.grid} strokeOpacity=".14" strokeWidth=".5" />
        </pattern>
        <mask id={gapId} maskUnits="userSpaceOnUse" x="0" y="0" width="720" height="640">
          <path d="M0 0H720V640H0Z" fill="white" />
          <path d="M -23.662015831524982 0 L 500 -244.18760826712423 L 500 244.18760826712423 Z" transform="translate(378.02667529115377 404.9783920951129) rotate(35)" fill="black" />
        </mask>
      </defs>
      {grid && (
      <path fill={`url(#${gridId})`} d="M0 0H720V640H0Z" />
      )}
      <path d="M265 100H335L530.0930354263446 500H69.90696457365542Z M300 245L221.97332470884623 404.9783920951129H378.02667529115377Z" fill={colors.ink} fillRule="evenodd" mask={`url(#${gapId})`} />
      <path d="M 0 0 C 0 -2 3 -3 8 -3.730461265239989 L 170 -79.27230188634977 Q 180 -83.93537846789975 175 -73.93537846789975 L 140 -26 Q 124 0 140 26 L 175 73.93537846789975 Q 180 83.93537846789975 170 79.27230188634977 L 8 3.730461265239989 C 3 3 0 2 0 0 Z" transform="translate(378.02667529115377 404.9783920951129) rotate(35)" fill={colors.cursor} />
      {guides && (
      <g fill="none" stroke={colors.guide} strokeWidth=".55" strokeOpacity=".6" strokeDasharray="3 4">
        <path d="M18 500H670 M300 18V515 M304.0186070852689 20L47.958998088191635 545 M295.9813929147311 20L552.0410019118084 545 M317.07064059980513 210L209.76947111531564 430 M282.92935940019487 210L390.23052888468436 430 M190 404.9783920951129H650 M220 100H385" />
        <path d="M-80 0H260 M-35 -16.32076803542495L235 109.58229966642467 M-35 16.32076803542495L235 -109.58229966642467" transform="translate(378.02667529115377 404.9783920951129) rotate(35)" />
        <circle cx="378.02667529115377" cy="404.9783920951129" r="7" />
        <path d="M365.02667529115377 404.9783920951129H391.02667529115377 M378.02667529115377 391.9783920951129V417.9783920951129" />
      </g>
      )}
      {annotations && (
      <g fill="none" stroke={colors.guide} strokeWidth=".55" strokeOpacity=".7">
        <path d="M72 270H98L135 286 M555 240H515L448 270 M300 553V523" strokeDasharray="3 4" />
        <circle cx="60" cy="270" r="12" />
        <circle cx="567" cy="240" r="12" />
        <circle cx="300" cy="565" r="12" />
      </g>
      )}
      {annotations && (
      <g fill={colors.ink} fontFamily="monospace" fontSize="11" textAnchor="middle">
        <text x="60" y="274">A</text>
        <text x="567" y="244">B</text>
        <text x="300" y="569">C</text>
      </g>
      )}
      {annotations && (
      <g fill={colors.ink} fontFamily="monospace" fontSize="9">
        <text x="40" y="612">A / LEFT SLOPE</text>
        <text x="210" y="612">B / RIGHT SLOPE</text>
        <text x="390" y="612">C / BASE</text>
        <text x="40" y="630">A = B = C : 95.02 UNITS, MEASURED PERPENDICULAR TO EACH EDGE</text>
      </g>
      )}
      {titleBlock && (
      <g fontFamily="monospace" fill={colors.ink}>
        <path d="M485 38H680 M485 70H680 M485 145H680" stroke={colors.guide} strokeWidth=".5" opacity=".55" />
        <text x="485" y="56" fontSize="10" letterSpacing="1.2">{figure} / {name}</text>
        <g fontSize="8" opacity=".7">
          <text x="485" y="86">{organization} / LOGO CONSTRUCTION</text>
          <text x="485" y="101">DESIGNED {year} · {revision}</text>
          <text x="485" y="116">SLOPES 64° / GAP 10 U</text>
          <text x="485" y="131">EDGE WIDTH 95.02 U / SVG</text>
        </g>
      </g>
      )}
      {annotations && (
      <g fill={colors.ink} fontFamily="monospace" fontSize="9">
        <text x="36" y="585">EQUAL EDGE WIDTH / 64° SLOPES / 10 UNIT GAP</text>
        <text x="440" y="575">TIP = INTERSECTION</text>
      </g>
      )}
    </svg>
  );
}
