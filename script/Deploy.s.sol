// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {IntentAuction} from "../src/IntentAuction.sol";
import {Executor} from "../src/Executor.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockSwapRouter} from "../src/mocks/MockSwapRouter.sol";
import {MockLendingPool} from "../src/mocks/MockLendingPool.sol";

/// @title Deploy — one-shot Sepolia deployment
/// @notice Deploys the full IntentAuction stack plus a deterministic mock backend
///         (MockERC20s, a fixed-price swap, a 1:1 lending pool) and wires everything
///         together. Writes the resulting address book to `deployments/sepolia.json`
///         so the frontend and CI can pick it up.
///
/// @dev Run with:
///         forge script script/Deploy.s.sol:Deploy \
///           --rpc-url $SEPOLIA_RPC_URL \
///           --private-key $PRIVATE_KEY \
///           --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY -vvvv
contract Deploy is Script {
    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPk);

        // 1. Core auction + executor (created inside auction's constructor).
        IntentAuction auction = new IntentAuction(deployer);
        Executor executor = auction.executor();
        console.log("IntentAuction:", address(auction));
        console.log("Executor:", address(executor));

        // 2. Mock tokens. 18-dec mWETH + 6-dec mUSDC + 6-dec aUSDC (lending receipt).
        MockERC20 mWeth = new MockERC20("Mock WETH", "mWETH", 18);
        MockERC20 mUsdc = new MockERC20("Mock USDC", "mUSDC", 6);
        MockERC20 aUsdc = new MockERC20("Mock aUSDC", "amUSDC", 6);
        console.log("mWETH:", address(mWeth));
        console.log("mUSDC:", address(mUsdc));
        console.log("aUSDC:", address(aUsdc));

        // 3. Mock backend.
        MockSwapRouter swap = new MockSwapRouter();
        MockLendingPool pool = new MockLendingPool();
        // 1 mWETH → 2000 mUSDC (simulates a $2000 ETH price on Sepolia, deterministically).
        swap.setRate(address(mWeth), address(mUsdc), 2_000e6);
        // 1 mUSDC deposit → 1 aUSDC (pre-yield, matches Aave's initial share ratio).
        pool.setAToken(address(mUsdc), address(aUsdc));
        console.log("MockSwapRouter:", address(swap));
        console.log("MockLendingPool:", address(pool));

        // 4. Wire the solver-target whitelist.
        auction.setTargetAllowed(address(swap), true);
        auction.setTargetAllowed(address(pool), true);

        // 5. Seed deployer with demo balances (so the UI has something to play with).
        mWeth.mint(deployer, 100 ether);
        mUsdc.mint(deployer, 1_000_000e6);

        vm.stopBroadcast();

        // 6. Write address book.
        string memory json = string.concat(
            "{\n",
            '  "chainId": 11155111,\n',
            '  "intentAuction": "', vm.toString(address(auction)), '",\n',
            '  "executor": "', vm.toString(address(executor)), '",\n',
            '  "mockWeth": "', vm.toString(address(mWeth)), '",\n',
            '  "mockUsdc": "', vm.toString(address(mUsdc)), '",\n',
            '  "aUsdc": "', vm.toString(address(aUsdc)), '",\n',
            '  "mockSwapRouter": "', vm.toString(address(swap)), '",\n',
            '  "mockLendingPool": "', vm.toString(address(pool)), '"\n',
            "}\n"
        );
        vm.writeFile("deployments/sepolia.json", json);
        console.log("Wrote deployments/sepolia.json");
    }
}
