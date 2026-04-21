"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { formatUnits, parseAbiItem, type Address, type Log } from "viem";
import { usePublicClient } from "wagmi";
import { ADDRESSES } from "../lib/contracts";
import { AddressPill } from "./Address";

/**
 * Matches `IIntentAuction.Settled`. Using `parseAbiItem` keeps the ABI
 * import footprint small.
 */
const SETTLED = parseAbiItem(
  "event Settled(bytes32 indexed intentId, address indexed solver, uint256 delivered, uint256 solverFee, uint256 userReceives)"
);

type SettledLog = {
  intentId: `0x${string}`;
  solver: Address;
  delivered: bigint;
  solverFee: bigint;
  userReceives: bigint;
  blockNumber: bigint;
  txHash: `0x${string}`;
};

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const CHUNK_SIZE = 9n;
const CONCURRENCY = 6;
const DEFAULT_MAX_LOOKBACK = 50n;

function deployBlock(): bigint | null {
  const raw = process.env.NEXT_PUBLIC_DEPLOY_BLOCK;
  if (!raw) return null;
  try {
    return BigInt(raw);
  } catch {
    return null;
  }
}

export function RecentSettlements() {
  const client = usePublicClient();
  const [items, setItems] = useState<SettledLog[] | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    async function run() {
      if (!client) return;
      if (ADDRESSES.intentAuction.toLowerCase() === ZERO_ADDRESS) {
        setErr("IntentAuction address is zero — check frontend/.env.local.");
        return;
      }
      try {
        const latest = await client.getBlockNumber();
        const deploy = deployBlock();
        const lookback = deploy !== null ? latest - deploy : DEFAULT_MAX_LOOKBACK;
        const fromBlock =
          deploy !== null ? deploy : latest > lookback ? latest - lookback : 0n;

        const ranges: Array<{ from: bigint; to: bigint }> = [];
        for (let start = fromBlock; start <= latest; start += CHUNK_SIZE + 1n) {
          const end = start + CHUNK_SIZE > latest ? latest : start + CHUNK_SIZE;
          ranges.push({ from: start, to: end });
        }

        const logs: Log[] = [];
        for (let i = 0; i < ranges.length; i += CONCURRENCY) {
          if (cancelled) return;
          const batch = await Promise.all(
            ranges.slice(i, i + CONCURRENCY).map((r) =>
              client.getLogs({
                address: ADDRESSES.intentAuction,
                event: SETTLED,
                fromBlock: r.from,
                toBlock: r.to,
              })
            )
          );
          for (const ls of batch) logs.push(...ls);
        }
        if (cancelled) return;
        setItems(
          logs
            .map(parseLog)
            .filter((x): x is SettledLog => x !== null)
            .sort((a, b) => Number(b.blockNumber - a.blockNumber))
            .slice(0, 10)
        );
      } catch (e) {
        if (!cancelled) setErr(e instanceof Error ? e.message : String(e));
      }
    }
    void run();
    return () => {
      cancelled = true;
    };
  }, [client]);

  if (err) return <div className="card text-sm text-bad">Failed to load: {err}</div>;
  if (!items) return <div className="card animate-pulse text-sm text-zinc-500">Loading…</div>;
  if (items.length === 0)
    return (
      <div className="card text-sm text-zinc-400">
        No settlements yet. They appear here the moment someone calls{" "}
        <span className="font-mono text-accent">settle()</span>.
      </div>
    );

  return (
    <div className="grid gap-2">
      {items.map((s) => (
        <Link
          key={s.txHash}
          href={`https://sepolia.etherscan.io/tx/${s.txHash}`}
          target="_blank"
          rel="noreferrer"
          className="card flex items-center justify-between gap-4 text-sm hover:border-accent"
        >
          <div className="flex min-w-0 items-center gap-3">
            <span className="text-xs uppercase tracking-wider text-good">settled</span>
            <AddressPill address={s.solver} />
          </div>
          <div className="flex shrink-0 items-center gap-4 text-xs text-zinc-400">
            <span className="font-mono text-zinc-200">
              {formatUnits(s.userReceives, 6)}
              <span className="text-zinc-500"> to user</span>
            </span>
            <span className="font-mono text-zinc-300">
              +{formatUnits(s.solverFee, 6)}
              <span className="text-zinc-500"> fee</span>
            </span>
            <span className="font-mono text-zinc-500">blk {s.blockNumber.toString()}</span>
          </div>
        </Link>
      ))}
    </div>
  );
}

function parseLog(log: Log): SettledLog | null {
  const l = log as Log & {
    args?: {
      intentId: `0x${string}`;
      solver: Address;
      delivered: bigint;
      solverFee: bigint;
      userReceives: bigint;
    };
  };
  if (!l.args || !log.transactionHash) return null;
  return {
    intentId: l.args.intentId,
    solver: l.args.solver,
    delivered: l.args.delivered,
    solverFee: l.args.solverFee,
    userReceives: l.args.userReceives,
    blockNumber: log.blockNumber ?? 0n,
    txHash: log.transactionHash,
  };
}
