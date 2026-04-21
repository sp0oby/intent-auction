// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockERC20} from "./MockERC20.sol";

/// @title MockSwapRouter
/// @notice Deterministic fixed-price swap used by solver calldata during tests and the
///         Sepolia demo. Burns `tokenIn` from the caller, mints `tokenOut` directly via
///         `MockERC20.mint`, so there's no liquidity to provision.
/// @dev Price is set per-pair by the admin: `price[tokenIn][tokenOut] = rate` means
///      1 unit of tokenIn yields `rate` units of tokenOut, scaled by `PRICE_SCALE`.
///      Decimals are assumed to be baked into `rate` by whoever sets the price.
contract MockSwapRouter {
    using SafeERC20 for IERC20;

    /// @notice PRICE_SCALE is what you divide by after multiplying by rate.
    /// @dev A rate of 2_000 * 1e6 means "1e18 WETH → 2_000e6 USDC" (i.e. $2000/ETH).
    uint256 public constant PRICE_SCALE = 1e18;

    /// @notice rates[tokenIn][tokenOut] = units of tokenOut per 1e18 of tokenIn.
    mapping(address => mapping(address => uint256)) public rates;

    /// @notice Admin (deployer) who can set rates. Unrestricted for a testnet demo.
    address public immutable admin;

    error NotAdmin();
    error NoPrice();

    event PriceSet(address indexed tokenIn, address indexed tokenOut, uint256 rate);
    event Swapped(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );

    constructor() {
        admin = msg.sender;
    }

    function setRate(address tokenIn, address tokenOut, uint256 rate) external {
        if (msg.sender != admin) revert NotAdmin();
        rates[tokenIn][tokenOut] = rate;
        emit PriceSet(tokenIn, tokenOut, rate);
    }

    /// @notice Quote a swap without executing it.
    function quote(address tokenIn, address tokenOut, uint256 amountIn)
        public
        view
        returns (uint256 amountOut)
    {
        uint256 rate = rates[tokenIn][tokenOut];
        if (rate == 0) revert NoPrice();
        // amountOut = amountIn * rate / PRICE_SCALE — multiply before divide to preserve precision.
        return (amountIn * rate) / PRICE_SCALE;
    }

    /// @notice Swap `amountIn` of `tokenIn` for `tokenOut` and send to `recipient`.
    /// @dev Executor will forwardApprove this router for `amountIn`, then call
    ///      `swap(tokenIn, tokenOut, amountIn, recipient)`.
    ///
    ///      NOTE: this mock mints fresh `tokenOut` rather than holding a real inventory.
    ///      That's fine on a testnet with a mock token whose `mint` is unrestricted,
    ///      and it means demos never run out of liquidity.
    function swap(address tokenIn, address tokenOut, uint256 amountIn, address recipient)
        external
        returns (uint256 amountOut)
    {
        amountOut = quote(tokenIn, tokenOut, amountIn);

        // Pull tokenIn from the caller. SafeERC20 handles non-standard return values.
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Mint tokenOut straight to recipient (Executor).
        MockERC20(tokenOut).mint(recipient, amountOut);

        emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut, recipient);
    }
}
