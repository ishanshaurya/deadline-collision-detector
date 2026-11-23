import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { createHmac, timingSafeEqual } from "crypto";
import * as Q from "./queries";

const COOKIE = "dcd_session";
export const MIN_PASSWORD_LENGTH = 6;

function sign(value: string) {
  const secret = process.env.SESSION_SECRET;
  if (!secret) throw new Error("SESSION_SECRET is not set. Copy web/.env.example to web/.env.");
  return createHmac("sha256", secret).update(value).digest("hex");
}

export async function createSession(userId: number) {
  (await cookies()).set(COOKIE, `${userId}.${sign(String(userId))}`, {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 24 * 7,
  });
}

export async function destroySession() {
  (await cookies()).delete(COOKIE);
}

export async function getUser() {
  const raw = (await cookies()).get(COOKIE)?.value;
  if (!raw) return null;
  const [id, mac] = raw.split(".");
  const expected = sign(id);
  if (!mac || mac.length !== expected.length) return null;
  if (!timingSafeEqual(Buffer.from(mac), Buffer.from(expected))) return null;
  const { rows } = await Q.userById.run(Number(id));
  return rows[0] ?? null;
}

export async function requireUser() {
  const user = await getUser();
  if (!user) redirect("/login");
  return user;
}

// The admin procedures and views also check the role inside the database.
export async function requireAdmin() {
  const user = await requireUser();
  if (user.role !== "ADMIN") redirect("/");
  return user;
}
