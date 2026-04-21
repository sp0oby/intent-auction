"use client";

import { useMemo, useState } from "react";
import { encodeFunctionData, formatUnits, parseUnits, type Address } from "viem";
import { useBlockNumber, useReadContract, useWriteContract } from "wagmi";
import { ABIS, ADDRESSES } from "../lib/contracts";
import { AddressPill } from "./Address";
import { Countdown } from "./Countdown";
import { TxButton } from "./TxButton";

type AuctionState = {
  intent: {
    user: Address;
    tokenIn: Address;
    amountIn: bigint;
    tokenOut: Address;
    minAmountOut: bigint;
    maxSolverFee: bigint;
    auctionDuration: bigint;
    nonce: bigint;
    deadline: bigint;
  };
  winningBid: {
    solver: Address;
    placedAtBlock: bigint;
    outputOffered: bigint;
    solverFee: bigint;
    target: Address;
    executionCalldata: `0x${string}`;
  };
  auctionEndBlock: bigint;
  status: number;
};

/**
 * Renders a single intent with:
 *   - signed parameters (read-only view)
 *   - current winning bid (if any)
 *   - bid form (for solvers)
 *   - settle button (anyone can call after the auction window)
 */
export function IntentDetail({ id }: { id: `0x${string}` }) {
  const { data, refetch } = useReadContract({
    address: ADDRESSES.intentAuction,
    abi: ABIS.IntentAuction,
    functionName: "getAuction",
    args: [id],
  });
  const { data: currentBlock } = useBlockNumber({ watch: true });
  const { writeContractAsync } = useWriteContract();
  const [bidErr, setBidErr] = useState<string | null>(null);
  const [settleErr, setSettleErr] = useState<string | null>(null);
  const [settling, setSettling] = useState(false);

  if (!data) return <div className="card animate-pulse text-sm text-zinc-500">Loading…</div>;

  const state = data as unknown as AuctionState;
  if (state.auctionEndBlock === 0n) {
    return <div className="card text-sm text-zinc-400">Intent not found.</div>;
  }

  const auctionOver = currentBlock !== undefined && currentBlock > state.auctionEndBlock;
  const netValue =
    state.winningBid.solver === "0x0000000000000000000000000000000000000000"
      ? null
      : state.winningBid.outputOffered - state.winningBid.solverFee;

  async function onSettle() {
    setSettleErr(null);
    setSettling(true);
    try {
      await writeContractAsync({
        address: ADDRESSES.intentAuction,
        abi: ABIS.IntentAuction,
        functionName: "settle",
        args: [id],
      });
      await refetch();
    } catch (e) {
      setSettleErr(e instanceof Error ? e.message : String(e));
    } finally {
      setSettling(false);
    }
  }

  return (
    <div className="space-y-6">
      <header className="space-y-1">
        <h1 className="font-mono text-sm text-zinc-400">{id}</h1>
        <div className="flex items-center gap-3 text-sm">
          <span className="text-zinc-400">from</span>
          <AddressPill address={state.intent.user} />
          <span className="text-zinc-600">·</span>
          {state.status === 0 ? (
            auctionOver ? (
              <span className="text-warn">waiting for settlement</span>
            ) : (
              <Countdown endBlock={state.auctionEndBlock} />
            )
          ) : state.status === 1 ? (
            <span className="text-good">settled</span>
          ) : (
            <span className="text-bad">cancelled</span>
          )}
        </div>
      </header>

      <section className="card space-y-3">
        <div className="flex items-center justify-between text-sm">
          <span className="text-zinc-400">Sends</span>
          <span className="font-mono">
            {formatUnits(state.intent.amountIn, 18)}{" "}
            {shortToken(state.intent.tokenIn)}
          </span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-zinc-400">Min receives</span>
          <span className="font-mono text-accent">
            {formatUnits(state.intent.minAmountOut, 6)} {shortToken(state.intent.tokenOut)}
          </span>
        </div>
        <div className="flex items-center justify-between text-sm">
          <span className="text-zinc-400">Max solver fee</span>
          <span className="font-mono">
            {formatUnits(state.intent.maxSolverFee, 6)} {shortToken(state.intent.tokenOut)}
          </span>
        </div>
      </section>

      <section className="card space-y-3">
        <h3 className="text-sm font-semibold uppercase tracking-wide text-zinc-400">
          Current best bid
        </h3>
        {netValue === null ? (
          <div className="text-sm text-zinc-500">No bids yet.</div>
        ) : (
          <>
            <div className="flex items-center justify-between text-sm">
              <span className="text-zinc-400">Solver</span>
              <AddressPill address={state.winningBid.solver} />
            </div>
            <div className="flex items-center justify-between text-sm">
              <span className="text-zinc-400">Net to user</span>
              <span className="font-mono text-good">
                {formatUnits(netValue, 6)} {shortToken(state.intent.tokenOut)}
              </span>
            </div>
            <div className="flex items-center justify-between text-xs text-zinc-500">
              <span>
                offered {formatUnits(state.winningBid.outputOffered, 6)} · fee{" "}
                {formatUnits(state.winningBid.solverFee, 6)}
              </span>
              <span>block {state.winningBid.placedAtBlock.toString()}</span>
            </div>
          </>
        )}
      </section>

      {state.status === 0 && !auctionOver ? (
        <BidForm
          id={id}
          tokenIn={state.intent.tokenIn}
          tokenOut={state.intent.tokenOut}
          amountIn={state.intent.amountIn}
          minAmountOut={state.intent.minAmountOut}
          maxFee={state.intent.maxSolverFee}
          onBid={refetch}
          err={bidErr}
          setErr={setBidErr}
        />
      ) : null}

      {state.status === 0 && auctionOver && netValue !== null ? (
        <div className="space-y-2">
          <TxButton
            label="Settle"
            pendingLabel="Settling…"
            pending={settling}
            onAction={onSettle}
          />
          {settleErr ? <div className="text-sm text-bad">{settleErr}</div> : null}
        </div>
      ) : null}
    </div>
  );
}

function BidForm({
  id,
  tokenIn,
  tokenOut,
  amountIn,
  minAmountOut,
  maxFee,
  onBid,
  err,
  setErr,
}: {
  id: `0x${string}`;
  tokenIn: Address;
  tokenOut: Address;
  amountIn: bigint;
  minAmountOut: bigint;
  maxFee: bigint;
  onBid: () => void;
  err: string | null;
  setErr: (s: string | null) => void;
}) {
  const [output, setOutput] = useState(formatUnits(minAmountOut, 6));
  const [fee, setFee] = useState(formatUnits(maxFee / 2n, 6));
  const [advanced, setAdvanced] = useState(false);
  const [target, setTarget] = useState<Address>(ADDRESSES.mockSwap);
  const [calldataRaw, setCalldataRaw] = useState<`0x${string}`>("0x");
  const [submitting, setSubmitting] = useState(false);

  /**
   * Preset calldata: call `MockSwapRouter.swap(tokenIn, tokenOut, amountIn, executor)`.
   * `recipient` must be the Executor — the Executor then verifies `delivered >= minAmountOut`
   * and splits the output between user and solver.
   */
  const presetCalldata = useMemo(
    () =>
      encodeFunctionData({
        abi: ABIS.MockSwapRouter,
        functionName: "swap",
        args: [tokenIn, tokenOut, amountIn, ADDRESSES.executor],
      }),
    [tokenIn, tokenOut, amountIn]
  );

  const effectiveTarget = advanced ? target : ADDRESSES.mockSwap;
  const effectiveCalldata = advanced ? calldataRaw : presetCalldata;

  const { writeContractAsync } = useWriteContract();

  async function onBidClick() {
    setErr(null);
    setSubmitting(true);
    try {
      await writeContractAsync({
        address: ADDRESSES.intentAuction,
        abi: ABIS.IntentAuction,
        functionName: "bidOnIntent",
        args: [
          id,
          parseUnits(output, 6),
          parseUnits(fee, 6),
          effectiveTarget,
          effectiveCalldata,
        ],
      });
      onBid();
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <section className="card space-y-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="text-sm font-semibold uppercase tracking-wide text-zinc-400">
            Place a solver bid
          </h3>
          <p className="mt-1 text-xs text-zinc-500">
            Commit to delivering ≥ output of tokenOut. You earn the fee if you win.
          </p>
        </div>
        <label className="flex cursor-pointer items-center gap-2 text-xs text-zinc-500">
          <input
            type="checkbox"
            className="accent-accent"
            checked={advanced}
            onChange={(e) => setAdvanced(e.target.checked)}
          />
          advanced
        </label>
      </div>

      <label className="block space-y-1">
        <span className="block text-xs text-zinc-400">Output offered (mUSDC)</span>
        <input className="field" value={output} onChange={(e) => setOutput(e.target.value)} />
      </label>
      <label className="block space-y-1">
        <span className="block text-xs text-zinc-400">Solver fee (mUSDC)</span>
        <input className="field" value={fee} onChange={(e) => setFee(e.target.value)} />
      </label>

      {advanced ? (
        <>
          <label className="block space-y-1">
            <span className="block text-xs text-zinc-400">Target</span>
            <input
              className="field"
              value={target}
              onChange={(e) => setTarget(e.target.value as Address)}
            />
          </label>
          <label className="block space-y-1">
            <span className="block text-xs text-zinc-400">Calldata (hex)</span>
            <textarea
              className="field h-24"
              value={calldataRaw}
              onChange={(e) => setCalldataRaw((e.target.value || "0x") as `0x${string}`)}
            />
          </label>
        </>
      ) : (
        <div className="rounded border border-surface2 bg-surface/60 p-3 text-xs text-zinc-500">
          Using preset: <span className="text-zinc-300">MockSwapRouter.swap</span> with
          this intent&apos;s tokens + amount. Uncheck <em>advanced</em> to use a custom
          target / calldata.
        </div>
      )}

      {err ? <div className="rounded bg-bad/10 p-3 text-sm text-bad">{err}</div> : null}

      <TxButton
        label="Place bid"
        pendingLabel="Placing…"
        pending={submitting}
        onAction={onBidClick}
      />
    </section>
  );
}

function shortToken(addr: Address): string {
  if (addr.toLowerCase() === ADDRESSES.mockWeth.toLowerCase()) return "mWETH";
  if (addr.toLowerCase() === ADDRESSES.mockUsdc.toLowerCase()) return "mUSDC";
  return `${addr.slice(0, 6)}…`;
}
