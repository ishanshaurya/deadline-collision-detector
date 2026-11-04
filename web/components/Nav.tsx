"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const NAV = [
  { href: "/", label: "dashboard" },
  { href: "/collisions", label: "collisions" },
  { href: "/tasks", label: "tasks" },
  { href: "/courses", label: "courses" },
  { href: "/availability", label: "availability" },
];

export function Nav() {
  const path = usePathname();
  return (
    <nav aria-label="Main">
      {NAV.map((n) => {
        const current = n.href === "/" ? path === "/" : path.startsWith(n.href);
        return (
          <Link key={n.href} href={n.href} className="nav-link" aria-current={current ? "page" : undefined}>
            {n.label}
          </Link>
        );
      })}
    </nav>
  );
}

export function Logo() {
  return (
    <div className="brand">
      <svg width="34" height="24" viewBox="0 0 34 24" aria-hidden>
        <circle cx="12" cy="12" r="10" fill="#7383D9" />
        <circle cx="22" cy="12" r="10" fill="#C4422A" fillOpacity="0.92" />
      </svg>
      <div className="brand-name">deadline<br />collision</div>
    </div>
  );
}
