export interface RemotionRenderOptions {
  template?: string;
  quality?: "draft" | "final";
}
export function renderWithRemotion(manifestPath: string, options: RemotionRenderOptions = {}): {
  backend: "remotion";
  manifestPath: string;
  options: RemotionRenderOptions;
} {
  return {
    backend: "remotion",
    manifestPath,
    options,
  };
}
