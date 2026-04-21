// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {IntentAuction} from "../src/IntentAuction.sol";
import {Executor} from "../src/Executor.sol";
import {IIntentAuction} from "../src/interfaces/IIntentAuction.sol";
import {IntentLib} from "../src/libraries/IntentLib.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockSwapRouter} from "../src/mocks/MockSwapRouter.sol";

/// @title Demo — end-to-end recruiter/CI demo script
/// @notice Reads `deployments/sepolia.json`, posts a signed intent from the deployer,
///         submits a winning bid from a secondary account, then settles. Useful as:
///           - A recruiter-facing "it really works" demo.
///           - A CI smoke test (run against a local anvil fork).
///
/// @dev To reuse on a local anvil: first run `forge script Deploy` against anvil, then
///      `forge script Demo` with the deployer PK.
contract Demo is Script {
    using stdJson for string;

    struct Ctx {
        IntentAuction auction;
        Executor executor;
        address mWeth;
        address mUsdc;
        address swap;
        uint256 userPk;
        uint256 solverPk;
        address user;
        address solver;
    }

    /// @notice Full flow in one invocation. Use on anvil (auto-rolls blocks) or for tracing.
    ///         On a live testnet the auction window check in `settle` will revert during
    ///         simulation — use `postAndBid()` + `settleOnly(bytes32)` there instead.
    function run() external {
        Ctx memory c = _loadCtx();
        (IIntentAuction.Intent memory i, bytes32 id, bytes memory sig) = _postIntent(c);
        _placeBid(c, id, i.amountIn);

        if (block.chainid == 31337) {
            vm.roll(block.number + i.auctionDuration + 1);
        }

        vm.startBroadcast(c.solverPk);
        c.auction.settle(id);
        console.log("Settled!");
        vm.stopBroadcast();

        console.log("User USDC:", MockERC20(c.mUsdc).balanceOf(c.user));
        console.log("Solver USDC:", MockERC20(c.mUsdc).balanceOf(c.solver));
        // Silence unused-variable warning on `sig`.
        sig;
    }

    /// @notice Stage 1 for live networks: post + bid. Writes the intent id to a file so
    ///         stage 2 can read it. Wait >= auctionDuration blocks before running stage 2.
    function postAndBid() external {
        Ctx memory c = _loadCtx();
        (IIntentAuction.Intent memory i, bytes32 id,) = _postIntent(c);
        _placeBid(c, id, i.amountIn);
        vm.writeFile("deployments/.demo_intent_id.txt", vm.toString(id));
        console.log("Wait >= %d blocks, then run `forge script Demo --sig settleOnly()`", i.auctionDuration);
    }

    /// @notice Stage 2 for live networks: settle the intent posted by `postAndBid()`.
    function settleOnly() external {
        Ctx memory c = _loadCtx();
        bytes32 id = vm.parseBytes32(vm.readFile("deployments/.demo_intent_id.txt"));

        vm.startBroadcast(c.solverPk);
        c.auction.settle(id);
        vm.stopBroadcast();

        console.log("Settled intent:");
        console.logBytes32(id);
        console.log("User USDC:", MockERC20(c.mUsdc).balanceOf(c.user));
        console.log("Solver USDC:", MockERC20(c.mUsdc).balanceOf(c.solver));
    }

    function _loadCtx() internal returns (Ctx memory c) {
        string memory json = vm.readFile("deployments/sepolia.json");
        c.auction = IntentAuction(payable(json.readAddress(".intentAuction")));
        c.executor = Executor(json.readAddress(".executor"));
        c.mWeth = json.readAddress(".mockWeth");
        c.mUsdc = json.readAddress(".mockUsdc");
        c.swap = json.readAddress(".mockSwapRouter");

        c.userPk = vm.envUint("PRIVATE_KEY");
        c.solverPk = vm.envOr("SOLVER_PRIVATE_KEY", c.userPk);
        c.user = vm.addr(c.userPk);
        c.solver = vm.addr(c.solverPk);
    }

    function _postIntent(Ctx memory c)
        internal
        returns (IIntentAuction.Intent memory i, bytes32 id, bytes memory sig)
    {
        i = IIntentAuction.Intent({
            user: c.user,
            tokenIn: c.mWeth,
            amountIn: 0.01 ether,
            tokenOut: c.mUsdc,
            minAmountOut: 19e6,
            maxSolverFee: 1e6,
            auctionDuration: 12,
            nonce: c.auction.nonces(c.user),
            deadline: block.timestamp + 1 hours
        });

        bytes32 digest = c.auction.hashIntentDigest(i);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(c.userPk, digest);
        sig = abi.encodePacked(r, s, v);
        id = IntentLib.intentId(digest, sig);

        vm.startBroadcast(c.userPk);
        MockERC20(c.mWeth).mint(c.user, i.amountIn);
        MockERC20(c.mWeth).approve(address(c.auction), i.amountIn);
        c.auction.postIntent(i, sig);
        vm.stopBroadcast();

        console.log("Posted intent id:");
        console.logBytes32(id);
    }

    function _placeBid(Ctx memory c, bytes32 id, uint256 amountIn) internal {
        bytes memory data = abi.encodeWithSelector(
            MockSwapRouter.swap.selector, c.mWeth, c.mUsdc, amountIn, address(c.executor)
        );
        vm.startBroadcast(c.solverPk);
        // Rate is 2000e6/1e18 → 0.01e18 WETH yields 20e6 USDC. Bid 20, take 0.5 fee.
        c.auction.bidOnIntent(id, 20e6, 5e5, c.swap, data);
        vm.stopBroadcast();
        console.log("Placed bid: 20 USDC out, 0.5 USDC fee");
    }
}
