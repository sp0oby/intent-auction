"use client";

import { useState } from "react";
import { formatUnits, parseUnits, type Address } from "viem";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { ABIS, ADDRESSES } from "../lib/contracts";
import { TxButton } from "./TxButton";

/**
 * Mock token faucet. The demo uses `MockERC20` with an unrestricted `mint`
 * function, so anyone can claim demo mWETH / mUSDC for themselves from the UI
 * without a backend. Useful for recruiters spinning up the app end-to-end.
 */
export function Faucet() {
  return (
    <div className="card space-y-4">
      <div>
        <h3 className="text-sm font-semibold uppercase tracking-wide text-zinc-400">
          Test token faucet
        </h3>
        <p className="mt-1 text-xs text-zinc-500">
          Mock tokens — free, unlimited, only work on this demo. Use them to
          play either role: post an intent as a user, or place a solver bid.
        </p>
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <MintButton
          token={ADDRESSES.mockWeth}
          decimals={18}
          amount="0.1"
          symbol="mWETH"
        />
        <MintButton
          token={ADDRESSES.mockUsdc}
          decimals={6}
          amount="200"
          symbol="mUSDC"
        />
      </div>
    </div>
  );
}

function MintButton({
  token,
  decimals,
  amount,
  symbol,
}: {
  token: Address;
  decimals: number;
  amount: string;
  symbol: string;
}) {
  const { address } = useAccount();
  const { writeContractAsync } = useWriteContract();
  const [pending, setPending] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const { data: balance, refetch } = useReadContract({
    address: token,
    abi: ABIS.MockERC20,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  });

  async function onMint() {
    if (!address) return;
    setErr(null);
    setPending(true);
    try {
      await writeContractAsync({
        address: token,
        abi: ABIS.MockERC20,
        functionName: "mint",
        args: [address, parseUnits(amount, decimals)],
      });
      await refetch();
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setPending(false);
    }
  }

  const fmt =
    balance !== undefined
      ? Number(formatUnits(balance as bigint, decimals)).toLocaleString(undefined, {
          maximumFractionDigits: 4,
        })
      : "—";

  return (
    <div className="flex flex-col gap-2 rounded border border-surface2 bg-surface/60 p-3">
      <div className="flex items-baseline justify-between gap-2">
        <span className="text-sm font-semibold tracking-tight">{symbol}</span>
        <span
          className="truncate font-mono text-xs text-zinc-400"
          title={`${fmt} ${symbol}`}
        >
          {fmt}
        </span>
      </div>
      <TxButton
        label={`Mint ${amount}`}
        pendingLabel="Minting…"
        pending={pending}
        onAction={onMint}
      />
      {err ? <div className="truncate text-xs text-bad" title={err}>{err}</div> : null}
    </div>
  );
}
