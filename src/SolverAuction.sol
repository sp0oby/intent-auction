// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IntentRegistry} from "./IntentRegistry.sol";

/// @title SolverAuction
/// @notice Handles the competitive bidding phase of an IntentAuction.
/// @dev Extends IntentRegistry so it reuses the auctions mapping + Ownable admin.
///      Bids are ranked by NET value to the user: `outputOffered - solverFee`.
///      Ties are rejected — a new bid must STRICTLY improve the current best — which
///      prevents griefing by replacing a competitor with an equally-good bid just to
///      claim the settlement slot.
abstract contract SolverAuction is IntentRegistry {
    // ----------------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------------

    /// @notice Target contracts the Executor is permitted to call with solver calldata.
    /// @dev Whitelisting targets is the primary defense when executing arbitrary solver
    ///      calldata. Without it, a solver could point calldata at the auction contract
    ///      itself, a token they control, or a malicious router. Admin controls this
    ///      list; keeping it small and audited is essential.
    mapping(address target => bool allowed) public allowedTargets;

    // ----------------------------------------------------------------------
    // Admin (owner only)
    // ----------------------------------------------------------------------

    /// @notice Flip a target's whitelist bit.
    /// @dev In production this admin key should be a Safe multisig (per
    ///      `security/SKILL.md` — never an EOA for long-lived permissions).
    function setTargetAllowed(address target, bool allowed) external onlyOwner {
        if (target == address(0)) revert InvalidAddress();
        allowedTargets[target] = allowed;
        emit TargetAllowed(target, allowed);
    }

    // ----------------------------------------------------------------------
    // Solver entrypoint
    // ----------------------------------------------------------------------

    /// @notice Submit (or improve upon) the leading bid for an intent.
    /// @dev All state changes here are pure mapping writes — no external calls, no
    ///      funds movement. Execution happens at settlement in `IntentAuction.settle`.
    ///
    ///      Griefing surface analysis:
    ///        - Calldata can be arbitrarily large → natural gas cost bounds spam.
    ///        - A bid fails if it doesn't strictly beat the current winner, so you
    ///          can't DOS the auction by spamming identical bids.
    ///        - Self-calls blocked: solver cannot target the auction itself.
    /// @param id              The posted intent's id.
    /// @param outputOffered   Amount of `tokenOut` the solver commits to deliver.
    /// @param solverFee       Fee the solver will collect (in `tokenOut`) on settlement.
    /// @param target          Whitelisted target the Executor will call.
    /// @param executionCalldata Raw calldata forwarded verbatim to `target`.
    function bidOnIntent(
        bytes32 id,
        uint256 outputOffered,
        uint256 solverFee,
        address target,
        bytes calldata executionCalldata
    ) external nonReentrant {
        AuctionState storage s = auctions[id];

        // ---- Checks ----
        if (s.status != 0) revert IntentNotActive();
        if (s.auctionEndBlock == 0) revert IntentNotActive(); // non-existent intent
        if (block.number > s.auctionEndBlock) revert AuctionEnded();

        if (outputOffered < s.intent.minAmountOut) revert BidBelowMin();
        if (solverFee > s.intent.maxSolverFee) revert FeeExceedsMax();
        if (solverFee >= outputOffered) revert FeeExceedsOutput();

        if (!allowedTargets[target]) revert TargetNotAllowed(target);
        // Hard stop: calling the auction itself would let a solver bypass access control
        // via delegate-style callbacks (even though we don't use delegatecall, defensive).
        if (target == address(this)) revert SelfCallForbidden();

        // Net value to user = what they receive after the solver takes their fee.
        // Strict improvement required: a later bidder cannot displace a tied competitor
        // (prevents griefing where a solver replaces a rival's bid at the last block
        // with equal economics just to steal the fee).
        uint256 newNet = outputOffered - solverFee;
        if (s.winningBid.solver != address(0)) {
            uint256 currentNet = s.winningBid.outputOffered - s.winningBid.solverFee;
            if (newNet <= currentNet) revert BidNotAnImprovement();
        }

        // ---- Effects ----
        // Replace the entire winning bid. We deliberately do NOT track historical bids
        // onchain — storage is expensive, and the BidPlaced event already provides full
        // auditability offchain.
        s.winningBid = Bid({
            solver: msg.sender,
            placedAtBlock: uint96(block.number),
            outputOffered: outputOffered,
            solverFee: solverFee,
            target: target,
            executionCalldata: executionCalldata
        });

        emit BidPlaced(id, msg.sender, outputOffered, solverFee, newNet);
    }
}
