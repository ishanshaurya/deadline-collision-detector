/** A cosine similarity (0 to 1) as a number and a bar. */
export function Similarity({ value }: { value: number }) {
  const pct = Math.max(0, Math.min(1, value)) * 100;
  return (
    <span className="sim" title="cosine similarity">
      <span className="sim-bar" aria-hidden><i style={{ width: `${pct}%` }} /></span>
      {value.toFixed(2)}
    </span>
  );
}
