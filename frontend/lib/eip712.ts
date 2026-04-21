import type { Address, WalletClient } from "viem";

/**
 * EIP-712 typed-data helper for signing intents from the browser.
 *
 * The `domain` name + version MUST match the contract's `EIP712("IntentAuction", "1")`
 * constructor arguments. The `Intent` struct ordering MUST match
 * `IntentLib.INTENT_TYPEHASH` byte-for-byte — if the contract-side typehash ever
 * changes, the test `test_TypehashMatchesExpectedString` will flag it, and we MUST
 * mirror that change here.
 */
export const INTENT_TYPES = {
  Intent: [
    { name: "user", type: "address" },
    { name: "tokenIn", type: "address" },
    { name: "amountIn", type: "uint256" },
    { name: "tokenOut", type: "address" },
    { name: "minAmountOut", type: "uint256" },
    { name: "maxSolverFee", type: "uint256" },
    { name: "auctionDuration", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
} as const;

export type Intent = {
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

export function domainFor(chainId: number, verifyingContract: Address) {
  return {
    name: "IntentAuction",
    version: "1",
    chainId,
    verifyingContract,
  } as const;
}

/**
 * Signs an Intent using the connected wallet's `signTypedData`.
 * Works for EOAs (ECDSA) and ERC-1271 smart wallets transparently, since the
 * contract-side verification uses OpenZeppelin's `SignatureChecker`.
 */
export async function signIntent(
  walletClient: WalletClient,
  chainId: number,
  verifyingContract: Address,
  intent: Intent
) {
  if (!walletClient.account) throw new Error("Wallet not connected");
  return await walletClient.signTypedData({
    account: walletClient.account,
    domain: domainFor(chainId, verifyingContract),
    types: INTENT_TYPES,
    primaryType: "Intent",
    message: intent,
  });
}
