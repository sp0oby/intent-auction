/**
 * Deployed contract addresses + ABI re-exports.
 *
 * `scripts/sync-abis.ts` overwrites the `ABIS` export below with the live ABIs
 * from the Foundry `out/` directory after each `forge build`. The addresses are
 * read from Next.js env vars so each deployment environment (preview, prod, anvil)
 * can override them without code changes.
 */
import type { Abi, Address } from "viem";
import { ABIS } from "./abis.generated";

const ADDRESS_RE = /^0x[0-9a-fA-F]{40}$/;
const ZERO: Address = "0x0000000000000000000000000000000000000000";

/**
 * IMPORTANT: Next.js only inlines `process.env.NEXT_PUBLIC_*` into the client
 * bundle when accessed with a LITERAL property name. A helper like
 * `process.env[someVar]` becomes `undefined` on the client. So we unpack
 * each var explicitly here.
 */
function parse(name: string, raw: string | undefined): Address {
  const v = raw?.trim();
  if (!v || !ADDRESS_RE.test(v)) {
    if (typeof window !== "undefined") {
      const reason = raw === undefined || raw === "" ? "undefined" : `"${raw}"`;
      console.warn(
        `[contracts] ${name} is not a valid 0x-prefixed address (got ${reason}). Check frontend/.env.local and restart the dev server.`
      );
    }
    return ZERO;
  }
  return v as Address;
}

export const ADDRESSES = {
  intentAuction: parse("NEXT_PUBLIC_INTENT_AUCTION_ADDRESS", process.env.NEXT_PUBLIC_INTENT_AUCTION_ADDRESS),
  executor: parse("NEXT_PUBLIC_EXECUTOR_ADDRESS", process.env.NEXT_PUBLIC_EXECUTOR_ADDRESS),
  mockWeth: parse("NEXT_PUBLIC_MOCK_WETH_ADDRESS", process.env.NEXT_PUBLIC_MOCK_WETH_ADDRESS),
  mockUsdc: parse("NEXT_PUBLIC_MOCK_USDC_ADDRESS", process.env.NEXT_PUBLIC_MOCK_USDC_ADDRESS),
  mockSwap: parse("NEXT_PUBLIC_MOCK_SWAP_ADDRESS", process.env.NEXT_PUBLIC_MOCK_SWAP_ADDRESS),
  mockLending: parse("NEXT_PUBLIC_MOCK_LENDING_ADDRESS", process.env.NEXT_PUBLIC_MOCK_LENDING_ADDRESS),
} as const;

export { ABIS };
export type Contracts = keyof typeof ABIS;

/** Runtime helper: build a viem `Contract` for a given name. */
export function contract(name: Contracts): { address: Address; abi: Abi } {
  const addressMap: Record<Contracts, Address> = {
    IntentAuction: ADDRESSES.intentAuction,
    Executor: ADDRESSES.executor,
    MockERC20: ADDRESSES.mockWeth, // address overridden per-token at call site
    MockSwapRouter: ADDRESSES.mockSwap,
    MockLendingPool: ADDRESSES.mockLending,
  };
  return { address: addressMap[name], abi: ABIS[name] };
}
