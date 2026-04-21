"use client";

import { useBlockNumber } from "wagmi";

/**
 * Live block-based countdown. Uses wagmi's `useBlockNumber({ watch: true })`
 * so the count refreshes as blocks arrive — no manual polling.
 */
export function Countdown({ endBlock }: { endBlock: bigint }) {
  const { data: current } = useBlockNumber({ watch: true });
  if (current === undefined) return <span className="text-zinc-500">…</span>;
  if (current >= endBlock) return <span className="text-warn">auction ended</span>;
  const remaining = endBlock - current;
  return (
    <span className="font-mono text-sm">
      <span className="text-accent">{remaining.toString()}</span>{" "}
      <span className="text-zinc-400">blocks left</span>
    </span>
  );
}
