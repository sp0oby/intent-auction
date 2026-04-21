// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockERC20} from "./MockERC20.sol";

/// @title MockLendingPool
/// @notice Minimal Aave-style lending pool used in the intent-auction demo.
///         `deposit(asset, amount, onBehalfOf)` pulls `asset` from the caller and
///         mints 1:1 aToken receipts to `onBehalfOf`. Good enough for the end-to-end
///         "swap then lend" intent pattern without running a real protocol.
/// @dev aTokens are plain MockERC20s created lazily by `setAToken`. The pool
///      requires `MockERC20.mint` privileges — since our MockERC20 is
///      public-mint, this works without any additional role management.
contract MockLendingPool {
    using SafeERC20 for IERC20;

    /// @notice Admin who can register aToken addresses.
    address public immutable admin;

    /// @notice Underlying asset → aToken contract.
    mapping(address underlying => address aToken) public aTokens;

    error NotAdmin();
    error NoAToken();

    event ATokenSet(address indexed underlying, address indexed aToken);
    event Deposited(
        address indexed caller,
        address indexed onBehalfOf,
        address indexed asset,
        uint256 amount
    );

    constructor() {
        admin = msg.sender;
    }

    function setAToken(address underlying, address aToken) external {
        if (msg.sender != admin) revert NotAdmin();
        aTokens[underlying] = aToken;
        emit ATokenSet(underlying, aToken);
    }

    /// @notice Deposit `amount` of `asset`; mint `amount` of aToken to `onBehalfOf`.
    /// @dev 1:1 conversion — fine for a demo, and matches Aave's share-minting
    ///      invariant at t=0 (before any yield accrues).
    function deposit(address asset, uint256 amount, address onBehalfOf) external {
        address aToken = aTokens[asset];
        if (aToken == address(0)) revert NoAToken();

        // Pull the underlying. SafeERC20 handles non-standard tokens.
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Mint aToken receipt to the beneficiary (Executor, which forwards to user).
        MockERC20(aToken).mint(onBehalfOf, amount);

        emit Deposited(msg.sender, onBehalfOf, asset, amount);
    }
}
