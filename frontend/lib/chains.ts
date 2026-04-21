import { sepolia } from "wagmi/chains";

/**
 * Only chain we care about for this project.
 * Keeping it as an exported constant makes the network-check flows easy (
 * components just check `chainId !== APP_CHAIN.id`).
 */
export const APP_CHAIN = sepolia;
