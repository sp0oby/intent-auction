"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { formatUnits, type Address, type Log, parseAbiItem } from "viem";
import { usePublicClient } from "wagmi";
import { ADDRESSES } from "../lib/contracts";
import { AddressPill } from "./Address";

type PostedIntent = {
  intentId: `0x${string}`;
  user: Address;
  tokenIn: Address;
  tokenOut: Address;
  amountIn: bigint;
  minAmountOut: bigint;
  auctionEndBlock: bigint;
  blockNumber: bigint;
};

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

/** Matches `IIntentAuction.IntentPosted`. */
const INTENT_POSTED = parseAbiItem(
  "event IntentPosted(bytes32 indexed intentId, address indexed user, address indexed tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, uint96 auctionEndBlock)"
);

/**
 * Free-tier Sepolia RPCs (notably Alchemy) cap `eth_getLogs` to a narrow
 * block range — Alchemy's current cap is 10 blocks. We scan in 9-block
 * chunks from the deploy block (or the last N blocks, whichever is tighter),
 * issuing up to `CONCURRENCY` requests in parallel.
 */
const CHUNK_SIZE = 9n;
const CONCURRENCY = 6;
// Hard cap on history to scan when no deploy block is provided, to keep
// the first-load time bounded on a free-tier RPC (~10 min at 12s/block).
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

/**
 * Intent feed — reads `IntentPosted` events via chunked `getLogs`. No indexer,
 * no backend; the contract emits enough info in the event to render the card
 * without a single extra eth_call.
 */
export function IntentFeed() {
  const client = usePublicClient();
  const [intents, setIntents] = useState<PostedIntent[] | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    async function fetchLogs() {
      if (!client) return;
      if (ADDRESSES.intentAuction.toLowerCase() === ZERO_ADDRESS) {
        setErr(
          "IntentAuction address is zero — check `frontend/.env.local` and restart `npm run dev`."
        );
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
                event: INTENT_POSTED,
                fromBlock: r.from,
                toBlock: r.to,
              })
            )
          );
          for (const ls of batch) logs.push(...ls);
        }

        if (cancelled) return;
        setIntents(
          logs
            .map(parseLog)
            .filter((x): x is PostedIntent => x !== null)
            .sort((a, b) => Number(b.blockNumber - a.blockNumber))
        );
      } catch (e) {
        if (!cancelled) setErr(e instanceof Error ? e.message : String(e));
      }
    }
    void fetchLogs();
    return () => {
      cancelled = true;
    };
  }, [client]);

  if (err) return <div className="card text-sm text-bad">Failed to load: {err}</div>;
  if (!intents) return <div className="card animate-pulse text-sm text-zinc-500">Loading…</div>;
  if (intents.length === 0)
    return (
      <div className="card text-sm text-zinc-400">
        No intents posted yet. <Link href="/create" className="text-accent">Create the first one</Link>.
      </div>
    );

  return (
    <div className="grid gap-3">
      {intents.map((i) => (
        <Link
          key={i.intentId}
          href={`/intent/${i.intentId}`}
          className="card flex items-center justify-between gap-6 hover:border-accent"
        >
          <div className="space-y-1">
            <div className="flex items-center gap-3 text-sm">
              <span className="text-zinc-400">from</span>
              <AddressPill address={i.user} />
            </div>
            <div className="font-mono text-sm">
              {formatUnits(i.amountIn, 18)} {shortToken(i.tokenIn)} →{" "}
              <span className="text-accent">≥ {formatUnits(i.minAmountOut, 6)}</span>{" "}
              {shortToken(i.tokenOut)}
            </div>
          </div>
          <div className="text-right text-xs text-zinc-400">
            ends at block{" "}
            <span className="font-mono text-accent">{i.auctionEndBlock.toString()}</span>
          </div>
        </Link>
      ))}
    </div>
  );
}

function shortToken(addr: Address): string {
  if (addr.toLowerCase() === ADDRESSES.mockWeth.toLowerCase()) return "mWETH";
  if (addr.toLowerCase() === ADDRESSES.mockUsdc.toLowerCase()) return "mUSDC";
  return `${addr.slice(0, 6)}…`;
}

function parseLog(log: Log): PostedIntent | null {
  const l = log as Log & {
    args?: {
      intentId: `0x${string}`;
      user: Address;
      tokenIn: Address;
      tokenOut: Address;
      amountIn: bigint;
      minAmountOut: bigint;
      auctionEndBlock: bigint;
    };
  };
  if (!l.args) return null;
  return {
    intentId: l.args.intentId,
    user: l.args.user,
    tokenIn: l.args.tokenIn,
    tokenOut: l.args.tokenOut,
    amountIn: l.args.amountIn,
    minAmountOut: l.args.minAmountOut,
    auctionEndBlock: l.args.auctionEndBlock,
    blockNumber: log.blockNumber ?? 0n,
  };
}
