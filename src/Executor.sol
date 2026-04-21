// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IExecutor} from "./interfaces/IExecutor.sol";
import {IIntentAuction} from "./interfaces/IIntentAuction.sol";

/// @title Executor
/// @notice Isolated contract that performs the atomic multi-call for a winning solver
///         bid. Splitting this out from IntentAuction is a deliberate security choice
///         — the Executor is the ONLY place that handles arbitrary solver calldata, so
///         keeping it small, stateless, and access-controlled limits the blast radius
///         if a solver ever manages to smuggle malicious data past the whitelist.
///
/// @dev Contract invariants (enforced per-call):
///         - Only `auction` may invoke entrypoints.
///         - Between external calls, the executor owns no tokens.
///         - Approvals granted to `target` are reset to zero before the function returns.
///         - Delivered amount is measured via `balanceOf` deltas, NOT solver return data
///           — the core griefing protection called out in `security/SKILL.md`.
///
/// @dev Fund flow: the auction PUSHES `amountIn` of `tokenIn` into this contract before
///      calling `executeWithFee`. The executor does not call `transferFrom(auction, ...)`
///      anywhere, so no auction→executor allowance is required — a small but real
///      simplification that also removes a whole class of allowance-mismatch bugs.
contract Executor is IExecutor, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The single caller allowed to invoke entrypoints.
    /// @dev Set once at construction. Immutable → cheaper and rules out "owner rotates
    ///      auction to attacker" attacks.
    address public immutable auction;

    error NotAuction();
    error ZeroAddress();

    /// @dev Params passed by the auction at settle time. Splits delivered tokenOut
    ///      between user (`delivered - solverFee`) and solver (`solverFee`).
    struct FeeSplitParams {
        ExecutionParams base;
        uint256 solverFee;
    }

    constructor(address auction_) {
        if (auction_ == address(0)) revert ZeroAddress();
        auction = auction_;
    }

    /// @inheritdoc IExecutor
    /// @dev Path for callers that don't need a fee split (reserved for future module
    ///      integrations — not used by IntentAuction.settle today).
    function execute(ExecutionParams calldata p)
        external
        override
        nonReentrant
        returns (uint256 delivered)
    {
        if (msg.sender != auction) revert NotAuction();
        delivered = _execute(p, address(0), 0);
    }

    /// @notice Fee-aware path used by IntentAuction.settle.
    /// @dev Assumes `p.base.amountIn` of `p.base.tokenIn` was already transferred into
    ///      this contract by the caller. Violating that assumption will cause the
    ///      subsequent `forceApprove` to succeed but the target's `transferFrom` to
    ///      revert (or, worse, consume an unrelated balance). Only invoked by the
    ///      auction which controls the push.
    function executeWithFee(FeeSplitParams calldata p)
        external
        nonReentrant
        returns (uint256 delivered)
    {
        if (msg.sender != auction) revert NotAuction();
        delivered = _execute(p.base, p.base.solver, p.solverFee);
    }

    // ----------------------------------------------------------------------
    // Internal — the meat of the executor
    // ----------------------------------------------------------------------

    function _execute(ExecutionParams calldata p, address feeRecipient, uint256 solverFee)
        internal
        returns (uint256 delivered)
    {
        IERC20 tokenIn = IERC20(p.tokenIn);
        IERC20 tokenOut = IERC20(p.tokenOut);

        // Snapshot BEFORE anything that could move tokenOut. `p.amountIn` of tokenIn is
        // already sitting here (pushed by the auction). If tokenIn == tokenOut, the
        // snapshot correctly includes it, so `delivered = balAfter - balBefore` measures
        // only the net gain produced by the solver's calldata.
        uint256 balBefore = tokenOut.balanceOf(address(this));

        // Approve target using forceApprove (OZ v5) — handles USDT's zero-reset quirk.
        tokenIn.forceApprove(p.target, p.amountIn);

        // Execute solver calldata. Bubble revert reasons for debuggability.
        (bool ok, bytes memory ret) = p.target.call(p.data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }

        // Always reset allowance — defensive against routers that don't consume the
        // entire approved amount. Leaving a dangling allowance to a whitelisted target
        // isn't immediately dangerous but costs nothing to clean up and prevents
        // future surprises if the whitelist ever shrinks.
        tokenIn.forceApprove(p.target, 0);

        // ---- Balance-delta verification (THE core safety check) ----
        uint256 balAfter = tokenOut.balanceOf(address(this));
        delivered = balAfter - balBefore;
        if (delivered < p.minDeliver) {
            revert IIntentAuction.DeliveredLessThanCommitted(p.minDeliver, delivered);
        }

        // ---- Fund distribution ----
        if (feeRecipient != address(0) && solverFee != 0) {
            if (solverFee >= delivered) revert IIntentAuction.FeeExceedsOutput();
            uint256 userReceives = delivered - solverFee;
            tokenOut.safeTransfer(p.user, userReceives);
            tokenOut.safeTransfer(feeRecipient, solverFee);
        } else {
            tokenOut.safeTransfer(p.user, delivered);
        }

        // Sweep any leftover `tokenIn` back to the user. Some routers leave residual
        // dust when they over-approve or partially fill.
        uint256 tokenInDust = tokenIn.balanceOf(address(this));
        if (tokenInDust != 0) {
            tokenIn.safeTransfer(p.user, tokenInDust);
        }

        emit Executed(p.intentId, p.solver, p.target, p.user, p.amountIn, delivered);
    }
}
