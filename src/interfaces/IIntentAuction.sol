// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IIntentAuction
/// @notice Shared types, events, and custom errors for the IntentAuction system.
/// @dev Split into its own interface file so external consumers (frontend, other contracts,
///      tests) can import the types without dragging in the whole implementation.
interface IIntentAuction {
    // ----------------------------------------------------------------------
    // Types
    // ----------------------------------------------------------------------

    /// @notice A user-signed intent. The EIP-712 struct hash of this is what the user signs.
    /// @dev Field ordering here must match `IntentLib.INTENT_TYPEHASH` — the struct hash
    ///      concatenates fields in declaration order.
    struct Intent {
        // Who owns the intent. The signature must recover to this address.
        address user;
        // Token the user will give up (pulled from `user` at settlement).
        address tokenIn;
        // Exact amount of `tokenIn` the user commits.
        uint256 amountIn;
        // Token the user expects back.
        address tokenOut;
        // Floor on output delivered to the user in `tokenOut`. Settlement reverts if less.
        uint256 minAmountOut;
        // Absolute cap on the solver fee (denominated in `tokenOut`, paid from delivered amount).
        uint256 maxSolverFee;
        // Length of the solver auction, in blocks, starting from `postIntent`.
        uint256 auctionDuration;
        // Per-user monotonic counter. Prevents signature replay. Must equal `nonces[user]`.
        uint256 nonce;
        // Unix timestamp after which the intent is no longer postable nor settleable.
        uint256 deadline;
    }

    /// @notice The current leading bid on an intent.
    struct Bid {
        // Solver that submitted the bid.
        address solver;
        // Block number the bid was placed at (used for deterministic tiebreaks and audit).
        uint96 placedAtBlock;
        // Amount of `tokenOut` the solver promises to deliver to the Executor during settlement.
        // MUST be >= intent.minAmountOut.
        uint256 outputOffered;
        // Fee the solver will receive (in `tokenOut`) upon successful settlement.
        // MUST be <= intent.maxSolverFee and <= outputOffered (no free money).
        uint256 solverFee;
        // Address the Executor will call with `executionCalldata`. MUST be whitelisted.
        address target;
        // Arbitrary calldata (e.g., encoded multicall: swap + deposit to lending pool).
        bytes executionCalldata;
    }

    /// @notice Stored auction state for an intent.
    struct AuctionState {
        Intent intent;
        Bid winningBid;
        uint96 auctionEndBlock;
        // Settlement state machine flag. 0 = active, 1 = settled, 2 = cancelled.
        // Using uint8 instead of enum keeps storage packing explicit.
        uint8 status;
    }

    // ----------------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------------

    /// @notice Emitted when a user posts a signed intent.
    event IntentPosted(
        bytes32 indexed intentId,
        address indexed user,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint96 auctionEndBlock
    );

    /// @notice Emitted every time a new winning bid is recorded.
    event BidPlaced(
        bytes32 indexed intentId,
        address indexed solver,
        uint256 outputOffered,
        uint256 solverFee,
        uint256 netValueToUser
    );

    /// @notice Emitted on successful settlement of the winning bid.
    event Settled(
        bytes32 indexed intentId,
        address indexed solver,
        uint256 delivered,
        uint256 solverFee,
        uint256 userReceives
    );

    /// @notice Emitted when a user cancels their own intent before settlement.
    event IntentCancelled(bytes32 indexed intentId, address indexed user);

    /// @notice Emitted when admin toggles a target on the solver target whitelist.
    event TargetAllowed(address indexed target, bool allowed);

    // ----------------------------------------------------------------------
    // Custom errors — cheaper than require strings and easier to assert in tests.
    // ----------------------------------------------------------------------

    error BadSignature();
    error BadNonce(uint256 expected, uint256 got);
    error IntentExpired();
    error IntentAlreadyPosted();
    error IntentNotActive();
    error IntentNotSettleable();
    error AuctionEnded();
    error AuctionNotEnded();
    error BidNotAnImprovement();
    error BidBelowMin();
    error FeeExceedsMax();
    error FeeExceedsOutput();
    error TargetNotAllowed(address target);
    error NotIntentOwner();
    error InvalidAmount();
    error InvalidAddress();
    error DeliveredLessThanCommitted(uint256 committed, uint256 delivered);
    error UnauthorizedCaller();
    error SelfCallForbidden();
}
