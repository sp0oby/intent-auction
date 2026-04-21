// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IExecutor
/// @notice Minimal interface for the atomic calldata executor used by IntentAuction.
/// @dev The Executor is intentionally isolated from the auction contract. The auction
///      pushes funds into it, the executor invokes solver-supplied calldata against a
///      whitelisted target, then the executor verifies the output delta before returning
///      funds to the user. Isolating this logic limits the blast radius of arbitrary
///      solver calldata: the executor holds no state, owns nothing between txs, and can
///      only be invoked by the registered auction contract.
interface IExecutor {
    /// @notice Emitted each time a solver bid is executed against a target.
    event Executed(
        bytes32 indexed intentId,
        address indexed solver,
        address indexed target,
        address user,
        uint256 amountIn,
        uint256 delivered
    );

    /// @notice Parameter struct keeps the execute() signature within stack limits.
    /// @dev Solidity stack depth (16 locals) is easily blown by inline params; the
    ///      struct pattern is the standard workaround used across the ecosystem
    ///      (Uniswap, 0x, Seaport).
    struct ExecutionParams {
        bytes32 intentId;
        address solver;
        address target;
        bytes data;
        address tokenIn;
        uint256 amountIn;
        address tokenOut;
        address user;
        uint256 minDeliver; // amount of tokenOut that MUST land in the executor after the call
    }

    /// @notice Execute solver-supplied calldata for an intent.
    /// @dev MUST be callable only by the registered IntentAuction. MUST revert if
    ///      `tokenOut.balanceOf(executor)` did not increase by at least `minDeliver`
    ///      between the start and end of the call.
    /// @return delivered Amount of `tokenOut` actually received by the executor.
    function execute(ExecutionParams calldata p) external returns (uint256 delivered);
}
