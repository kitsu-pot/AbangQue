import { readdir, readFile } from 'node:fs/promises';
export async function applyTestMigrations(pool) {
  const directory = new URL('../migrations/', import.meta.url);
  for (const name of (await readdir(directory)).filter(n => /^\d+.*\.sql$/.test(n)).sort())
    await pool.query(await readFile(new URL(name, directory), 'utf8'));
}
