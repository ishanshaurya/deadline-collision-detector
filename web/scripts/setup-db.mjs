import { readFileSync, readdirSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import pg from "pg";

const dbDir = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "db");
const files = readdirSync(dbDir).filter((f) => f.endsWith(".sql")).sort();

if (!process.env.DATABASE_URL) {
  console.error("DATABASE_URL is not set. Copy web/.env.example to web/.env.");
  process.exit(1);
}

const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
await client.connect();
try {
  for (const f of files) {
    process.stdout.write(`running ${f} ... `);
    await client.query(readFileSync(join(dbDir, f), "utf8"));
    console.log("ok");
  }
  console.log("Database ready. Demo login: aarav@dcd.edu / password123");
} catch (e) {
  console.error("\nFAILED:", e.message);
  process.exitCode = 1;
} finally {
  await client.end();
}
