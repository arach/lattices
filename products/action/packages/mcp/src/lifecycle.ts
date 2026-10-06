/**
 * The MCP server lives only as long as the client that started it. Claude Code and other clients
 * normally close stdin or kill the child on exit, but a client that crashes or is killed hard leaves
 * the server running forever. Exit when stdin closes, or when the parent process is gone.
 */
export function exitWithParent(options: { pollMs?: number; exit?: (code: number) => void } = {}): () => void {
  const exit = options.exit ?? ((code: number) => process.exit(code));
  const parent = process.ppid;
  const onEnd = () => exit(0);
  process.stdin.once("end", onEnd);
  process.stdin.once("close", onEnd);
  const timer = setInterval(() => {
    if (!parentAlive(parent)) exit(0);
  }, options.pollMs ?? 15_000);
  timer.unref?.();
  return () => {
    clearInterval(timer);
    process.stdin.off("end", onEnd);
    process.stdin.off("close", onEnd);
  };
}

export function parentAlive(pid: number): boolean {
  if (pid <= 1 || process.ppid !== pid) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "EPERM";
  }
}
