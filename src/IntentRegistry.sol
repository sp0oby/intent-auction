// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IIntentAuction} from "./interfaces/IIntentAuction.sol";
import {IntentLib} from "./libraries/IntentLib.sol";

/// @title IntentRegistry
/// @notice Abstract base of the IntentAuction stack. Owns all persistent state
///         (intents, nonces, target whitelist) and handles EIP-712 verification of
///         user-signed intents. SolverAuction and IntentAuction inherit this so they
///         share a single storage layout — keeping everything on one chain of
///         inheritance avoids the delegatecall/proxy storage pitfalls flagged in
///         `security/SKILL.md` and makes the final deployed bytecode self-contained.
/// @dev Inherits:
///         - `EIP712`  → battle-tested domain-separator + typed-data digest helpers.
///         - `Ownable` → admin-gated target whitelist (managed by SolverAuction).
///         - `ReentrancyGuard` → belt-and-suspenders on external funds-moving paths.
abstract contract IntentRegistry is IIntentAuction, EIP712, Ownable, ReentrancyGuard {
    using IntentLib for Intent;

    // ----------------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------------

    /// @notice Full auction state indexed by intent id.
    /// @dev `intentId` is derived in `postIntent` from the EIP-712 digest + signature
    ///      (see IntentLib.intentId). Two distinct intents can never collide.
    mapping(bytes32 intentId => AuctionState state) public auctions;

    /// @notice Monotonic per-user nonce. A valid intent must carry `nonce == nonces[user]`.
    /// @dev Incremented on both `postIntent` (consume) and `increaseNonce` (manual
    ///      invalidation of outstanding offchain signatures).
    mapping(address user => uint256 nonce) public nonces;

    // ----------------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------------

    /// @param initialOwner Admin address that can manage the target whitelist.
    constructor(address initialOwner)
        EIP712("IntentAuction", "1") // name + version MUST match the frontend's typed-data payload.
        Ownable(initialOwner)
    {
        if (initialOwner == address(0)) revert InvalidAddress();
    }

    // ----------------------------------------------------------------------
    // External entrypoints
    // ----------------------------------------------------------------------

    /// @notice Publish a user-signed intent and open its auction window.
    /// @dev Uses `SignatureChecker.isValidSignatureNow` so BOTH EOA (ECDSA) and smart
    ///      contract (EIP-1271) signatures are supported — important because EIP-7702
    ///      and ERC-4337 wallets are mainstream on Sepolia.
    ///
    ///      Anyone may broadcast the intent (gas sponsorship), but the signature must
    ///      recover to `i.user`. This is the gasless-UX benefit of the intent pattern.
    /// @param i   The intent being posted.
    /// @param sig The user's EIP-712 signature over `hashTypedDataV4(hashIntent(i))`.
    /// @return id The unique identifier for this posted intent.
    function postIntent(Intent calldata i, bytes calldata sig)
        external
        nonReentrant
        returns (bytes32 id)
    {
        // ---- Checks ----
        // Reject trivially broken intents early to save gas on the happy path.
        if (i.user == address(0) || i.tokenIn == address(0) || i.tokenOut == address(0)) {
            revert InvalidAddress();
        }
        if (i.amountIn == 0 || i.auctionDuration == 0) revert InvalidAmount();
        // Max fee cap must leave the user at least some output; otherwise the intent is nonsense.
        if (i.maxSolverFee >= i.minAmountOut) revert InvalidAmount();
        if (block.timestamp >= i.deadline) revert IntentExpired();
        if (i.nonce != nonces[i.user]) revert BadNonce(nonces[i.user], i.nonce);

        // Build the EIP-712 digest and verify against the declared user.
        bytes32 digest = _hashTypedDataV4(IntentLib.hashIntent(i));
        if (!SignatureChecker.isValidSignatureNow(i.user, digest, sig)) revert BadSignature();

        // Derive stable id. Because it includes the signature, two distinct sigs for the
        // same payload produce different ids — but replay is still blocked by the nonce.
        id = IntentLib.intentId(digest, sig);

        // Reject if this exact (intent, sig) pair already registered. Should never happen
        // under the nonce rule, but explicit guard > implicit invariant.
        if (auctions[id].auctionEndBlock != 0) revert IntentAlreadyPosted();

        // ---- Effects ----
        // Burn the nonce first so any re-entrant postIntent attempt (e.g. from a malicious
        // token hook during a callback if we ever took one) would fail the nonce check.
        unchecked {
            nonces[i.user] = i.nonce + 1;
        }

        // Snap the auction window. Using block.number (not timestamp) for the auction
        // length matches how MEV searchers reason about timing and is harder to grief.
        uint96 auctionEndBlock = uint96(block.number + i.auctionDuration);

        // Store full auction state. Bid fields are left zero — no winning bid yet.
        AuctionState storage s = auctions[id];
        s.intent = i;
        s.auctionEndBlock = auctionEndBlock;
        s.status = 0; // active

        emit IntentPosted(
            id, i.user, i.tokenIn, i.tokenOut, i.amountIn, i.minAmountOut, auctionEndBlock
        );
    }

    /// @notice Invalidate a specific posted intent. Only the intent's user can call.
    /// @dev Useful if the user wants to withdraw their intent before any bid arrives, or
    ///      if they change their mind mid-auction. Settlement is blocked after this.
    function cancelIntent(bytes32 id) external nonReentrant {
        AuctionState storage s = auctions[id];
        if (s.status != 0) revert IntentNotActive();
        if (s.intent.user != msg.sender) revert NotIntentOwner();

        s.status = 2; // cancelled
        emit IntentCancelled(id, msg.sender);
    }

    /// @notice Bump the caller's nonce by one, invalidating any outstanding offchain intents.
    /// @dev Lightweight escape hatch (analogous to Uniswap's Permit2 nonce bump). Use
    ///      when a private key is potentially compromised or when a batch of sigs should
    ///      be wholesale revoked.
    function increaseNonce() external {
        unchecked {
            nonces[msg.sender] += 1;
        }
    }

    // ----------------------------------------------------------------------
    // View helpers
    // ----------------------------------------------------------------------

    /// @notice Expose the EIP-712 domain separator so the frontend can sanity-check it.
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Digest for a given intent — frontend debugging aid.
    function hashIntentDigest(Intent calldata i) external view returns (bytes32) {
        return _hashTypedDataV4(IntentLib.hashIntent(i));
    }

    /// @notice Convenience accessor. Returns the full `AuctionState` as a memory copy.
    function getAuction(bytes32 id) external view returns (AuctionState memory) {
        return auctions[id];
    }
}
