"use client";

import { Suspense } from "react";
import { useSearchParams } from "next/navigation";
import { FLASH_KEYS } from "@/lib/flash";

function FlashMessage() {
  const params = useSearchParams();
  const error = params.get(FLASH_KEYS.error);
  const ok = params.get(FLASH_KEYS.ok);
  if (error) return <div className="flash flash-error" role="alert">⚠ {error}</div>;
  if (ok) return <div className="flash flash-ok" role="status">✓ {ok}</div>;
  return null;
}

export function Flash() {
  return (
    <Suspense>
      <FlashMessage />
    </Suspense>
  );
}
