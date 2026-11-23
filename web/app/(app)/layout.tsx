import { requireUser } from "@/lib/session";
import { logout } from "@/app/actions";
import { Flash } from "@/components/Flash";
import { Logo, Nav } from "@/components/Nav";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();
  return (
    <div className="shell">
      <aside className="sidebar">
        <Logo />
        <Nav isAdmin={user.role === "ADMIN"} />
        <div className="who">
          <strong>{user.name}</strong>
          <span className="who-email">{user.email}</span>
          {user.role === "ADMIN" && <span className="pill pill-ink" style={{ alignSelf: "flex-start", marginTop: 6 }}>admin</span>}
          <form action={logout} style={{ marginTop: 10 }}>
            <button className="btn btn-sm">sign out</button>
          </form>
        </div>
      </aside>
      <main className="content">
        <Flash />
        {children}
      </main>
    </div>
  );
}
