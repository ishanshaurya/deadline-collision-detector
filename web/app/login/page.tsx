import Link from "next/link";
import { redirect } from "next/navigation";
import { login, register } from "@/app/actions";
import { getUser, MIN_PASSWORD_LENGTH } from "@/lib/session";
import { Flash } from "@/components/Flash";
import { Logo } from "@/components/Nav";

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ mode?: string }> }) {
  if (await getUser()) redirect("/");
  const isRegister = (await searchParams).mode === "register";

  return (
    <div className="login-wrap">
      <div className="login-card">
        <Logo />
        <div>
          <h1 style={{ fontSize: 30 }}>{isRegister ? "make an account" : "welcome back"}</h1>
          <p className="muted" style={{ margin: "6px 0 0" }}>See which deadlines collide before they do.</p>
        </div>
        <Flash />
        {isRegister ? (
          <form action={register} className="form">
            <label>name<input name="name" required /></label>
            <label>email<input name="email" type="email" required /></label>
            <label>password<input name="password" type="password" minLength={MIN_PASSWORD_LENGTH} required /></label>
            <button className="btn btn-ink">create account</button>
            <p className="muted">
              Have an account? <Link href="/login" style={{ fontWeight: 600 }}>Sign in</Link>
            </p>
          </form>
        ) : (
          <form action={login} className="form">
            <label>email<input name="email" type="email" defaultValue="aarav@dcd.edu" required /></label>
            <label>password<input name="password" type="password" defaultValue="password123" required /></label>
            <button className="btn btn-ink">sign in</button>
            <p className="muted">
              Demo users: aarav@, diya@, kabir@dcd.edu (password123).{" "}
              <Link href="/login?mode=register" style={{ fontWeight: 600 }}>Register</Link>
            </p>
          </form>
        )}
      </div>
    </div>
  );
}
