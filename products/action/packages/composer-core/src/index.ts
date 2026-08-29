export interface FocusWindow {
  startMs: number;
  endMs: number;
  x: number;
  y: number;
  width: number;
  height: number;
}
export interface RenderManifest {
  sourceVideo: string;
  subtitles?: string;
  focusWindows?: FocusWindow[];
  chapters?: Array<{ title: string; atMs: number }>;
}
