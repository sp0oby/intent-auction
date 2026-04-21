// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IIntentAuction} from "../interfaces/IIntentAuction.sol";

/// @title IntentLib
/// @notice EIP-712 typehash + struct hashing for user intents.
/// @dev Kept as a library so the same hashing rules can be reused by the main contract,
///      by scripts, and by any future extension (e.g., meta-executor) without ambiguity.
///
///      The typehash is the keccak256 of the string form of the struct — field order MUST
///      match the `Intent` struct in `IIntentAuction.sol`. If you change one, you MUST change
///      the other; tests verify this stays in sync.
library IntentLib {
    /// @notice Canonical EIP-712 typehash for the Intent struct.
    /// @dev Matches the Solidity struct byte-for-byte. A mismatch between the string here
    ///      and the struct members would silently break signature verification, which is
    ///      why `test/IntentRegistry.t.sol::test_TypehashMatchesStruct` asserts this.
    bytes32 internal constant INTENT_TYPEHASH = keccak256(
        "Intent(address user,address tokenIn,uint256 amountIn,address tokenOut,uint256 minAmountOut,uint256 maxSolverFee,uint256 auctionDuration,uint256 nonce,uint256 deadline)"
    );

    /// @notice Hash an Intent struct per EIP-712.
    /// @dev Returns only the struct hash; the final digest (prefixed with the domain
    ///      separator) is computed by the caller via `_hashTypedDataV4`.
    function hashIntent(IIntentAuction.Intent calldata i) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                INTENT_TYPEHASH,
                i.user,
                i.tokenIn,
                i.amountIn,
                i.tokenOut,
                i.minAmountOut,
                i.maxSolverFee,
                i.auctionDuration,
                i.nonce,
                i.deadline
            )
        );
    }

    /// @notice Memory variant (used from tests / scripts that can't pass calldata).
    function hashIntentMemory(IIntentAuction.Intent memory i) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                INTENT_TYPEHASH,
                i.user,
                i.tokenIn,
                i.amountIn,
                i.tokenOut,
                i.minAmountOut,
                i.maxSolverFee,
                i.auctionDuration,
                i.nonce,
                i.deadline
            )
        );
    }

    /// @notice Stable identifier for a posted intent.
    /// @dev Derived from the user-signed digest + the signature itself. Two different
    ///      signatures over the same Intent payload produce different ids (e.g., from
    ///      signature malleability or from the same user signing twice after nonce bump).
    function intentId(bytes32 digest, bytes memory signature) internal pure returns (bytes32) {
        return keccak256(abi.encode(digest, signature));
    }
}
