"use client";

import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { http } from "wagmi";
import { APP_CHAIN } from "./chains";

/**
 * Wagmi/RainbowKit config.
 *
 * The Alchemy key goes into the RPC URL so we don't rely on the public fallback
 * (which is rate-limited). The WalletConnect project id is required by RainbowKit.
 * Both are pulled from `NEXT_PUBLIC_*` env vars — they are safe to ship to the
 * browser (WalletConnect project IDs are public by design).
 */
const alchemyKey = process.env.NEXT_PUBLIC_ALCHEMY_API_KEY ?? "demo";
const wcProjectId =
  process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "intent-auction-demo";

export const wagmiConfig = getDefaultConfig({
  appName: "IntentAuction",
  projectId: wcProjectId,
  chains: [APP_CHAIN],
  transports: {
    [APP_CHAIN.id]: http(
      `https://eth-sepolia.g.alchemy.com/v2/${alchemyKey}`
    ),
  },
  ssr: true,
});
