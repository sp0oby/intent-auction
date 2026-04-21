"use client";

import { useState } from "react";
import { parseUnits, type Address, type PublicClient, type WalletClient } from "viem";
import {
  useAccount,
  useChainId,
  usePublicClient,
  useReadContract,
  useWalletClient,
  useWriteContract,
} from "wagmi";
import { ABIS, ADDRESSES } from "../lib/contracts";
import { signIntent, type Intent } from "../lib/eip712";
import { TxButton } from "./TxButton";

/**
 * CreateForm
 *
 * Two-step user flow:
 *   1. Sign intent (EIP-712) — happens locally in the wallet, no onchain tx.
 *   2. Post signed intent — posting is the ONLY onchain step, and ANYONE can
 *      do it (so a relayer/keeper can sponsor gas if desired). For the demo
 *      we have the user post their own intent from the same wallet.
 *
 * We keep pending state per-step so the user always knows what's happening:
 *   "Sign intent" → "Signing…"
 *   "Post onchain" → "Posting…" → "Awaiting confirmation…"
 */
export function CreateForm() {
  const { address } = useAccount();
  const chainId = useChainId();
  const { data: walletClient } = useWalletClient();
  const publicClient = usePublicClient();
  const { writeContractAsync } = useWriteContract();

  const [amountIn, setAmountIn] = useState("0.01");
  const [minOut, setMinOut] = useState("19");
  const [maxFee, setMaxFee] = useState("1");
  const [duration, setDuration] = useState("12");

  const [sig, setSig] = useState<`0x${string}` | null>(null);
  const [signedIntent, setSignedIntent] = useState<Intent | null>(null);
  const [signing, setSigning] = useState(false);
  const [posting, setPosting] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);

  // Read user nonce so we can bake it into the signed intent.
  const { data: nonce } = useReadContract({
    address: ADDRESSES.intentAuction,
    abi: ABIS.IntentAuction,
    functionName: "nonces",
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address) },
  });

  async function onSign() {
    setErr(null);
    if (!address || !walletClient) {
      setErr("connect wallet first");
      return;
    }
    setSigning(true);
    try {
      const intent: Intent = {
        user: address,
        tokenIn: ADDRESSES.mockWeth,
        amountIn: parseUnits(amountIn, 18),
        tokenOut: ADDRESSES.mockUsdc,
        minAmountOut: parseUnits(minOut, 6),
        maxSolverFee: parseUnits(maxFee, 6),
        auctionDuration: BigInt(duration || "0"),
        nonce: (nonce as bigint | undefined) ?? 0n,
        deadline: BigInt(Math.floor(Date.now() / 1000) + 3600),
      };
      const signature = await signIntent(
        walletClient,
        chainId,
        ADDRESSES.intentAuction,
        intent
      );
      setSig(signature);
      setSignedIntent(intent);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setSigning(false);
    }
  }

  async function onPost() {
    if (!sig || !signedIntent || !address) return;
    setErr(null);
    setPosting(true);
    try {
      // Approve the auction to pull tokenIn at settle time. This is the only
      // ERC20 approval required for the whole lifecycle.
      await approveIfNeeded(
        publicClient,
        walletClient,
        signedIntent.tokenIn,
        address,
        ADDRESSES.intentAuction,
        signedIntent.amountIn
      );

      const hash = await writeContractAsync({
        address: ADDRESSES.intentAuction,
        abi: ABIS.IntentAuction,
        functionName: "postIntent",
        args: [signedIntent as unknown as Record<string, unknown>, sig],
      });
      setTxHash(hash);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setPosting(false);
    }
  }

  return (
    <form className="card space-y-5" onSubmit={(e) => e.preventDefault()}>
      <Labeled label="You send (mWETH)">
        <input className="field" value={amountIn} onChange={(e) => setAmountIn(e.target.value)} />
      </Labeled>
      <Labeled label="Minimum you accept (mUSDC)" hint="Floor on output; anything less and settle reverts.">
        <input className="field" value={minOut} onChange={(e) => setMinOut(e.target.value)} />
      </Labeled>
      <Labeled label="Max solver fee (mUSDC)" hint="Upper bound on the fee a solver can take.">
        <input className="field" value={maxFee} onChange={(e) => setMaxFee(e.target.value)} />
      </Labeled>
      <Labeled label="Auction duration (blocks)" hint="~12 seconds per block on Sepolia.">
        <input className="field" value={duration} onChange={(e) => setDuration(e.target.value)} />
      </Labeled>

      {err ? <div className="rounded bg-bad/10 p-3 text-sm text-bad">{err}</div> : null}

      {!sig ? (
        <TxButton label="Sign intent" pendingLabel="Signing…" pending={signing} onAction={onSign} />
      ) : txHash ? (
        <div className="rounded bg-good/10 p-3 text-center text-sm text-good">
          Posted! tx{" "}
          <a
            className="underline"
            href={`https://sepolia.etherscan.io/tx/${txHash}`}
            target="_blank"
            rel="noreferrer"
          >
            {txHash.slice(0, 10)}…
          </a>
        </div>
      ) : (
        <TxButton
          label="Post onchain"
          pendingLabel="Posting…"
          pending={posting}
          onAction={onPost}
        />
      )}
    </form>
  );
}

function Labeled({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block space-y-1">
      <span className="block text-xs uppercase tracking-wide text-zinc-400">{label}</span>
      {children}
      {hint ? <span className="block text-xs text-zinc-500">{hint}</span> : null}
    </label>
  );
}

async function approveIfNeeded(
  publicClient: PublicClient | undefined,
  walletClient: WalletClient | undefined,
  token: Address,
  owner: Address,
  spender: Address,
  minAmount: bigint
) {
  if (!publicClient || !walletClient || !walletClient.account) return;
  const allowance = (await publicClient.readContract({
    address: token,
    abi: ABIS.MockERC20,
    functionName: "allowance",
    args: [owner, spender],
  })) as bigint;
  if (allowance >= minAmount) return;

  await walletClient.writeContract({
    account: walletClient.account,
    chain: walletClient.chain,
    address: token,
    abi: ABIS.MockERC20,
    functionName: "approve",
    args: [spender, 2n ** 256n - 1n],
  });
}
