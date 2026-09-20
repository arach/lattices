import type { CompanionRelease } from './companion-release';

export type CompanionInstallPhase = 'checking' | 'downloading' | 'verifying' | 'installing' | 'installed';

/** Native filesystem/security adapter. Commit MUST be an atomic no-replace rename.
 * Verify MUST check bundle identity, Developer ID, notarization, OS and architecture.
 * Staging must be private, on the destination filesystem, and operation-owned.
 */
export interface CompanionInstallOperations {
  findInstalled(bundleID: string): Promise<string | undefined>;
  createStaging(): Promise<string>;
  download(release: CompanionRelease, staging: string, signal?: AbortSignal): Promise<string>;
  mountReadOnly(artifact: string, signal?: AbortSignal): Promise<string>;
  stageExpectedApp(mount: string, staging: string, release: CompanionRelease, signal?: AbortSignal): Promise<string>;
  verify(app: string, release: CompanionRelease, signal?: AbortSignal): Promise<void>;
  commitExclusive(app: string, release: CompanionRelease): Promise<string>;
  detach(mount: string): Promise<void>;
  removeStaging(staging: string): Promise<void>;
}

export type CompanionInstallResult =
  | { status: 'already-installed'; path: string; cleanupErrors: string[] }
  | { status: 'installed'; path: string; cleanupErrors: string[] }
  | { status: 'cancelled'; cleanupErrors: string[] }
  | { status: 'failed'; message: string; cleanupErrors: string[] };

/** Transaction orchestration only: never launches or terminates a companion.
 * Cancellation stops before commit. Once committed, installation is successful
 * even if cancellation or cleanup fails; callers must not retry as a new install.
 */
export async function installCompanion(
  release: CompanionRelease,
  operations: CompanionInstallOperations,
  options: { signal?: AbortSignal; onPhase?: (phase: CompanionInstallPhase) => void } = {},
): Promise<CompanionInstallResult> {
  const cleanupErrors: string[] = [];
  let staging: string | undefined;
  let mount: string | undefined;
  let installedPath: string | undefined;
  let result: CompanionInstallResult;
  const checkpoint = (phase: CompanionInstallPhase) => {
    options.signal?.throwIfAborted();
    options.onPhase?.(phase);
    options.signal?.throwIfAborted();
  };
  try {
    checkpoint('checking');
    const existing = await operations.findInstalled(release.bundleID);
    if (existing) return { status: 'already-installed', path: existing, cleanupErrors };
    options.signal?.throwIfAborted();
    staging = await operations.createStaging();
    checkpoint('downloading');
    const artifact = await operations.download(release, staging, options.signal);
    options.signal?.throwIfAborted();
    mount = await operations.mountReadOnly(artifact, options.signal);
    options.signal?.throwIfAborted();
    const app = await operations.stageExpectedApp(mount, staging, release, options.signal);
    checkpoint('verifying');
    await operations.verify(app, release, options.signal);
    checkpoint('installing');
    // Recheck after slow download/validation; commit still must reject races.
    const appeared = await operations.findInstalled(release.bundleID);
    if (appeared) {
      result = { status: 'already-installed', path: appeared, cleanupErrors };
    } else {
      options.signal?.throwIfAborted();
      installedPath = await operations.commitExclusive(app, release);
      result = { status: 'installed', path: installedPath, cleanupErrors };
    }
  } catch (error) {
    result = options.signal?.aborted
      ? { status: 'cancelled', cleanupErrors }
      : { status: 'failed', message: error instanceof Error ? error.message : String(error), cleanupErrors };
  } finally {
    // Cleanup is deliberately not given the cancelled operation signal.
    let canRemoveStaging = true;
    if (mount) {
      try { await operations.detach(mount); }
      catch (error) { canRemoveStaging = false; cleanupErrors.push(`Detach failed; staging retained: ${String(error)}`); }
    }
    if (staging && canRemoveStaging) {
      try { await operations.removeStaging(staging); }
      catch (error) { cleanupErrors.push(`Staging cleanup failed: ${String(error)}`); }
    }
  }
  if (installedPath) {
    // UI progress handlers cannot change a committed result.
    try { options.onPhase?.('installed'); } catch { /* installation already committed */ }
    return { status: 'installed', path: installedPath, cleanupErrors };
  }
  return result!;
}
