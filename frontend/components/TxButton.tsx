"use client";

import { useAccount, useChainId, useSwitchChain } from "wagmi";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { APP_CHAIN } from "../lib/chains";
import type { ReactNode } from "react";

export type TxButtonProps = {
  /** What to render on the button when it's doing the actual action. */
  label: ReactNode;
  /** Label during pending onchain state. */
  pendingLabel?: ReactNode;
  /** Whether we're currently submitting/awaiting receipt. */
  pending?: boolean;
  /** Disable even when all prerequisites are met (e.g. form invalid). */
  disabled?: boolean;
  /** Action to run once connected + on the right chain. */
  onAction: () => void | Promise<void>;
};

/**
 * Four-state action button:
 *   1. Not connected → "Connect wallet" (opens RainbowKit modal).
 *   2. Wrong network → "Switch network" (triggers wallet switch).
 *   3. Ready → `label` (runs onAction).
 *   4. Pending → `pendingLabel` / "Submitting…".
 *
 * This matches the pattern from `frontend-ux/SKILL.md` so every action in the
 * app follows the same progression — users never have to wonder "what do I
 * click first?".
 */
export function TxButton(props: TxButtonProps) {
  const { label, pendingLabel = "Submitting…", pending = false, disabled = false, onAction } = props;
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { switchChain, isPending: switchPending } = useSwitchChain();
  const { openConnectModal } = useConnectModal();

  if (!isConnected || !address) {
    return (
      <button className="btn btn-primary w-full" onClick={() => openConnectModal?.()}>
        Connect wallet
      </button>
    );
  }

  if (chainId !== APP_CHAIN.id) {
    return (
      <button
        className="btn btn-primary w-full"
        disabled={switchPending}
        onClick={() => switchChain({ chainId: APP_CHAIN.id })}
      >
        {switchPending ? "Switching…" : `Switch to ${APP_CHAIN.name}`}
      </button>
    );
  }

  return (
    <button
      className="btn btn-primary w-full"
      disabled={disabled || pending}
      onClick={() => {
        void onAction();
      }}
    >
      {pending ? pendingLabel : label}
    </button>
  );
}
