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
              netValue === null ? (
                <span className="text-zinc-500">expired · no bids</span>
              ) : (
                <span className="text-warn">ready to settle</span>
              )
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
          currentOutput={
            netValue === null ? null : state.winningBid.outputOffered
          }
          currentFee={
            netValue === null ? null : state.winningBid.solverFee
          }
          currentNet={netValue}
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

      {state.status === 0 && auctionOver && netValue === null ? (
        <div className="card space-y-1 border-warn/40 text-sm">
          <div className="font-semibold text-warn">Auction expired with no bids</div>
          <p className="text-xs leading-relaxed text-zinc-400">
            This intent&apos;s auction window closed without anyone bidding.
            It can&apos;t be settled (no bid to execute), and only the original
            signer (<span className="font-mono">{state.intent.user.slice(0, 6)}…{state.intent.user.slice(-4)}</span>)
            can cancel it. The easiest path is to{" "}
            <a href="/create" className="text-accent hover:underline">
              post a fresh intent
            </a>{" "}
            and bid on it before the window closes (~12 Sepolia blocks,
            ~2.5 minutes).
          </p>
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
  currentOutput,
  currentFee,
  currentNet,
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
  /** Current winning bid's outputOffered, or null if no bid yet. */
  currentOutput: bigint | null;
  /** Current winning bid's solverFee, or null if no bid yet. */
  currentFee: bigint | null;
  /** Current winning bid's net value (outputOffered - solverFee), or null. */
  currentNet: bigint | null;
  onBid: () => void;
  err: string | null;
  setErr: (s: string | null) => void;
}) {
  /**
   * Defaults.
   *   - No existing bid: offer exactly `minAmountOut` at half the max fee.
   *   - Existing bid: keep `outputOffered` the same but cut the fee by 0.000001
   *     mUSDC (the 6-decimal atomic unit). That's the cheapest way to strictly
   *     improve net-to-user while staying within the user's fee cap. If the
   *     current fee is already 0, bump `outputOffered` by 1 atomic unit instead.
   */
  const defaults = useMemo(() => {
    if (currentOutput === null || currentFee === null) {
      return {
        output: formatUnits(minAmountOut, 6),
        fee: formatUnits(maxFee / 2n, 6),
      };
    }
    if (currentFee > 0n) {
      return {
        output: formatUnits(currentOutput, 6),
        fee: formatUnits(currentFee - 1n, 6),
      };
    }
    return {
      output: formatUnits(currentOutput + 1n, 6),
      fee: "0",
    };
  }, [currentOutput, currentFee, minAmountOut, maxFee]);

  const [output, setOutput] = useState(defaults.output);
  const [fee, setFee] = useState(defaults.fee);
  const [advanced, setAdvanced] = useState(false);
  const [target, setTarget] = useState<Address>(ADDRESSES.mockSwap);
  const [calldataRaw, setCalldataRaw] = useState<`0x${string}`>("0x");
  const [submitting, setSubmitting] = useState(false);

  /**
   * Live validation that mirrors the contract's checks in `bidOnIntent`.
   * Running this in the UI means the user never sees the wallet's
   * "transaction is likely to fail" warning — we disable the button first.
   */
  const validation = useMemo(() => {
    let outputWei: bigint;
    let feeWei: bigint;
    try {
      outputWei = parseUnits(output || "0", 6);
      feeWei = parseUnits(fee || "0", 6);
    } catch {
      return { ok: false as const, reason: "Invalid number." };
    }
    if (outputWei < minAmountOut) {
      return {
        ok: false as const,
        reason: `Output must be ≥ ${formatUnits(minAmountOut, 6)} (user's floor).`,
      };
    }
    if (feeWei > maxFee) {
      return {
        ok: false as const,
        reason: `Fee must be ≤ ${formatUnits(maxFee, 6)} (user's cap).`,
      };
    }
    if (feeWei >= outputWei) {
      return { ok: false as const, reason: "Fee must be strictly less than output." };
    }
    const newNet = outputWei - feeWei;
    if (currentNet !== null && newNet <= currentNet) {
      return {
        ok: false as const,
        reason: `Bid must strictly improve current best net (${formatUnits(currentNet, 6)}). Yours is ${formatUnits(newNet, 6)}.`,
      };
    }
    return { ok: true as const, newNet };
  }, [output, fee, minAmountOut, maxFee, currentNet]);

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
    if (!validation.ok) {
      setErr(validation.reason);
      return;
    }
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

      {currentNet !== null ? (
        <div className="rounded border border-surface2 bg-surface/60 p-3 text-xs text-zinc-400">
          Current best net to user:{" "}
          <span className="font-mono text-zinc-200">
            {formatUnits(currentNet, 6)} mUSDC
          </span>
          . Your bid must strictly beat it.
        </div>
      ) : null}

      <label className="block space-y-1">
        <span className="block text-xs text-zinc-400">Output offered (mUSDC)</span>
        <input className="field" value={output} onChange={(e) => setOutput(e.target.value)} />
      </label>
      <label className="block space-y-1">
        <span className="block text-xs text-zinc-400">Solver fee (mUSDC)</span>
        <input className="field" value={fee} onChange={(e) => setFee(e.target.value)} />
      </label>

      <div
        className={`text-xs ${
          validation.ok ? "text-good" : "text-warn"
        }`}
      >
        {validation.ok ? (
          <>
            Your bid: net{" "}
            <span className="font-mono">
              {formatUnits(validation.newNet, 6)} mUSDC
            </span>{" "}
            to user.
          </>
        ) : (
          validation.reason
        )}
      </div>

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
        disabled={!validation.ok}
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
