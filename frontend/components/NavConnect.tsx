"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";

/**
 * Small wrapper so we can customize chain/show-balance behavior in one place.
 * RainbowKit handles the four-state flow internally:
 *   Not connected → "Connect Wallet"
 *   Wrong network → "Wrong network"
 *   Connected OK → address + chain pill
 */
export function NavConnect() {
  return (
    <ConnectButton
      accountStatus={{ smallScreen: "avatar", largeScreen: "full" }}
      chainStatus={{ smallScreen: "icon", largeScreen: "full" }}
      showBalance={false}
    />
  );
}
