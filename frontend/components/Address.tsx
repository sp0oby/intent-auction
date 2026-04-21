import type { Address } from "viem";

/**
 * Compact address display: `0x12ab…cd34`, monospaced. Always use this component
 * (never raw strings) — consistency matters for trust UX, per the
 * `frontend-ux/SKILL.md` guidance.
 */
export function AddressPill({ address, className = "" }: { address: Address; className?: string }) {
  const short = `${address.slice(0, 6)}…${address.slice(-4)}`;
  return (
    <span
      className={`inline-flex items-center rounded-md bg-surface2 px-2 py-0.5 font-mono text-xs ${className}`}
      title={address}
    >
      {short}
    </span>
  );
}
