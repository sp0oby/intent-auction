// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20
/// @notice Simple configurable ERC20 for local tests and Sepolia demos.
/// @dev Unlike the production OZ ERC20, this mock:
///        - lets anyone mint (trivially so demos just work),
///        - accepts a custom `decimals` at construction so tests can exercise
///          USDC-style 6-decimal tokens alongside 18-decimal ones,
///        - is explicitly NOT safe for mainnet use — it's marked "Mock" for the record.
contract MockERC20 is ERC20 {
    uint8 private immutable _dec;

    constructor(string memory name_, string memory symbol_, uint8 decimals_)
        ERC20(name_, symbol_)
    {
        _dec = decimals_;
    }

    /// @dev Override so e.g. MockUSDC has 6 decimals and MockWETH has 18.
    function decimals() public view override returns (uint8) {
        return _dec;
    }

    /// @notice Unrestricted mint — for testnet demos only.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
