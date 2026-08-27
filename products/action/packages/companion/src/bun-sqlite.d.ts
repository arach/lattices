declare module "bun:sqlite" {
  export class Database {
    constructor(filename?: string, options?: Record<string, unknown>);
    exec(sql: string): void;
    run(sql: string, ...params: unknown[]): { changes: number; lastInsertRowid: number | bigint };
    query<T = Record<string, unknown>>(sql: string): {
      get(...params: unknown[]): T | null;
      all(...params: unknown[]): T[];
      run(...params: unknown[]): { changes: number; lastInsertRowid: number | bigint };
    };
    close(): void;
  }
}
