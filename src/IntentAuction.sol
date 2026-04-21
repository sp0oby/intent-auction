// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {SolverAuction} from "./SolverAuction.sol";
import {IntentRegistry} from "./IntentRegistry.sol";
import {IExecutor} from "./interfaces/IExecutor.sol";
import {Executor} from "./Executor.sol";

/// @title IntentAuction
/// @notice Main entrypoint for the onchain Intent Solver Marketplace. Ties together:
///           - IntentRegistry  → stores EIP-712 signed intents + nonces
///           - SolverAuction   → short competitive bidding window
///           - Executor        → isolated atomic calldata execution at settlement
///
/// @dev Deploys OWN concrete `settle()` which is the only state transition that moves
///      real funds. All funds flow is linear and auditable:
///
///        user  ──safeTransferFrom──▶  executor
///        executor ──target.call(data)──▶  external protocols (swap, lend, ...)
///        executor ──safeTransfer──▶  user (delivered - solverFee)
///        executor ──safeTransfer──▶  solver (solverFee)
///
///      CEI ordering: status flipped BEFORE any interaction. If the external call
///      reverts, the whole tx reverts and the status flip is undone — no partial state.
contract IntentAuction is SolverAuction {
    using SafeERC20 for IERC20;

    /// @notice Address of the isolated executor that runs solver calldata.
    /// @dev Immutable. The executor, in turn, has this contract's address burned in as
    ///      its own `auction` field — forming a locked, 1:1 pair.
    Executor public immutable executor;

    constructor(address initialOwner) IntentRegistry(initialOwner) {
        // Deploy a fresh Executor bound to this auction. Because the Executor's `auction`
        // is immutable, there is no way to retarget it at a different auction later.
        // The auction → executor relationship is 1:1 and cannot be changed.
        executor = new Executor(address(this));
    }

    // ------------------------------------------------------------------
    // Settlement
    // ------------------------------------------------------------------

    /// @notice Execute the winning solver bid for a posted intent.
    /// @dev ANYONE can call this after the auction window ends — matches the
    ///      "nothing is automatic" principle from `concepts/SKILL.md`. If no one
    ///      calls it, nothing happens; the solver has the strongest incentive to
    ///      settle (they earn the fee), so in practice they do.
    ///
    ///      If the intent had no valid winning bid, settle reverts with
    ///      `IntentNotSettleable` — the user's funds are never touched. They can
    ///      either cancel the intent or wait for the deadline.
    function settle(bytes32 id) external nonReentrant {
        AuctionState storage s = auctions[id];

        // ---- Checks ----
        if (s.status != 0) revert IntentNotActive();
        if (s.auctionEndBlock == 0) revert IntentNotActive();
        if (block.number <= s.auctionEndBlock) revert AuctionNotEnded();
        // Re-check the user-signed deadline. An auction that ran past the user's desired
        // deadline should not settle — the user may have already revoked tokenIn approval
        // and a stale settlement would be hostile.
        if (block.timestamp >= s.intent.deadline) revert IntentExpired();
        if (s.winningBid.solver == address(0)) revert IntentNotSettleable();

        // ---- Effects: flip state BEFORE any interaction (CEI) ----
        s.status = 1; // settled

        // Snapshot into memory for the interaction block — the storage pointer becomes
        // unreliable after external calls that could theoretically re-enter (we have
        // nonReentrant, but the pattern is disciplined anyway).
        address user = s.intent.user;
        address tokenIn = s.intent.tokenIn;
        address tokenOut = s.intent.tokenOut;
        uint256 amountIn = s.intent.amountIn;
        uint256 minAmountOut = s.intent.minAmountOut;
        address solver = s.winningBid.solver;
        uint256 outputOffered = s.winningBid.outputOffered;
        uint256 solverFee = s.winningBid.solverFee;
        address target = s.winningBid.target;
        bytes memory data = s.winningBid.executionCalldata;

        // ---- Interactions ----
        // 1. Pull the user's input tokens directly INTO the executor.
        //    Pushing (not approve-then-pull) avoids the need for the executor to carry
        //    a standing allowance from this contract and keeps the fund flow linear.
        IERC20(tokenIn).safeTransferFrom(user, address(executor), amountIn);

        // 2. Invoke the executor with fee split. Executor will:
        //    - call `target` with `data`,
        //    - verify the delivered `tokenOut` >= `outputOffered`,
        //    - send (delivered - solverFee) to the user and `solverFee` to the solver.
        IExecutor.ExecutionParams memory base = IExecutor.ExecutionParams({
            intentId: id,
            solver: solver,
            target: target,
            data: data,
            tokenIn: tokenIn,
            amountIn: amountIn,
            tokenOut: tokenOut,
            user: user,
            minDeliver: outputOffered
        });

        uint256 delivered =
            executor.executeWithFee(Executor.FeeSplitParams({base: base, solverFee: solverFee}));

        // Final safety re-check: even though the executor enforces `delivered >=
        // outputOffered`, we also want to ensure the user's net after fee is at least
        // their signed `minAmountOut`. Earlier checks in `bidOnIntent` enforce this
        // invariant at bid-time, but re-check here guards against any future refactor
        // that loosens those bid-time checks.
        uint256 userReceives = delivered - solverFee;
        if (userReceives < minAmountOut) revert DeliveredLessThanCommitted(minAmountOut, userReceives);

        emit Settled(id, solver, delivered, solverFee, userReceives);
    }

    // ------------------------------------------------------------------
    // Convenience views for the frontend
    // ------------------------------------------------------------------

    /// @notice Returns the current best-bid net value for a given intent.
    /// @return netValue `outputOffered - solverFee` of the winning bid, or 0 if none.
    function currentNetValue(bytes32 id) external view returns (uint256) {
        Bid storage b = auctions[id].winningBid;
        if (b.solver == address(0)) return 0;
        return b.outputOffered - b.solverFee;
    }

    /// @notice Returns remaining blocks in the auction window (0 after it's closed).
    function blocksLeft(bytes32 id) external view returns (uint256) {
        uint96 end = auctions[id].auctionEndBlock;
        if (end == 0 || block.number >= end) return 0;
        return end - block.number;
    }
}
