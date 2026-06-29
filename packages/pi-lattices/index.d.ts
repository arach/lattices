export interface PiToolResultContent {
  type: "text";
  text: string;
}

export interface PiToolResult {
  content: PiToolResultContent[];
  details?: unknown;
  isError?: boolean;
}

export interface PiToolDefinition {
  name: string;
  label: string;
  description: string;
  parameters: unknown;
  execute(
    toolCallId: string,
    params?: Record<string, unknown>,
    signal?: AbortSignal,
    onUpdate?: unknown,
    ctx?: unknown
  ): Promise<PiToolResult>;
}

export interface PiExtensionApi {
  on(event: "session_start", handler: (event: unknown, ctx: unknown) => void | Promise<void>): void;
  registerTool(tool: PiToolDefinition): void;
}

export interface LatticesToolMetadata {
  name: string;
  method: string | null;
  description: string;
  parameters: unknown;
}

export declare const LATTICES_TOOLS: LatticesToolMetadata[];
export default function latticesPiExtension(pi: PiExtensionApi): void;
