// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IntentAuction} from "../src/IntentAuction.sol";
import {Executor} from "../src/Executor.sol";
import {IExecutor} from "../src/interfaces/IExecutor.sol";
import {IIntentAuction} from "../src/interfaces/IIntentAuction.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockSwapRouter} from "../src/mocks/MockSwapRouter.sol";
import {MockLendingPool} from "../src/mocks/MockLendingPool.sol";

import {SigUtils} from "./utils/SigUtils.sol";

/// @title IntentAuction end-to-end tests
/// @notice Covers the full `postIntent → bidOnIntent → settle` pipeline using the
///         mock DEX and lending pool. Exercises both happy-path and adversarial
///         behavior on the Executor (griefing, slippage).
contract IntentAuctionTest is SigUtils {
    IntentAuction internal auction;
    Executor internal executor;
    MockERC20 internal weth;
    MockERC20 internal usdc;
    MockSwapRouter internal swap;

    uint256 internal userPk = 0xA11CE;
    address internal user;
    address internal admin = address(this);
    address internal solver = makeAddr("solver");

    function setUp() public {
        user = vm.addr(userPk);
        auction = new IntentAuction(admin);
        executor = auction.executor();

        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        swap = new MockSwapRouter();
        // 1 WETH (1e18) → 2000 USDC (2000e6). Rate = 2000e6 * 1e18 / 1e18 = 2000e6.
        // But PRICE_SCALE == 1e18, so amountOut = amountIn * rate / 1e18.
        // For 1e18 WETH in → 2000e6 USDC out: rate = 2000e6.
        swap.setRate(address(weth), address(usdc), 2_000e6);

        auction.setTargetAllowed(address(swap), true);

        // Fund user with WETH.
        weth.mint(user, 10 ether);
        vm.prank(user);
        weth.approve(address(auction), type(uint256).max);
    }

    // ----------------------------------------------------------------------
    // Happy path: settle delivers correct amounts, splits fee
    // ----------------------------------------------------------------------

    function test_Settle_HappyPath() public {
        // Post intent: 1 WETH → ≥1990 USDC, max fee 5 USDC.
        IIntentAuction.Intent memory i = _intent(1 ether, 1_990e6, 5e6, 10);
        bytes memory sig = signIntent(userPk, address(auction), i);
        bytes32 id = auction.postIntent(i, sig);

        // Solver bids: offer 2000 USDC, take 3 USDC fee (net 1997 to user).
        bytes memory data = _encodeSwapCall(address(weth), address(usdc), 1 ether, address(executor));
        vm.prank(solver);
        auction.bidOnIntent(id, 2_000e6, 3e6, address(swap), data);

        // Roll past auction window.
        vm.roll(block.number + 11);

        // Anyone settles.
        vm.expectEmit(true, true, true, true);
        emit IIntentAuction.Settled(id, solver, 2_000e6, 3e6, 1_997e6);
        auction.settle(id);

        assertEq(usdc.balanceOf(user), 1_997e6, "user receives output - fee");
        assertEq(usdc.balanceOf(solver), 3e6, "solver receives fee");
        assertEq(weth.balanceOf(user), 9 ether, "user sent 1 WETH");
        assertEq(weth.balanceOf(address(executor)), 0, "executor holds no residual weth");
        assertEq(usdc.balanceOf(address(executor)), 0, "executor holds no residual usdc");
        assertEq(usdc.balanceOf(address(auction)), 0, "auction holds no residual usdc");
    }

    // ----------------------------------------------------------------------
    // Failure modes on settle
    // ----------------------------------------------------------------------

    function test_RevertWhen_SettleBeforeAuctionEnds() public {
        (bytes32 id,) = _postAndBid(2_000e6, 3e6);
        vm.expectRevert(IIntentAuction.AuctionNotEnded.selector);
        auction.settle(id);
    }

    function test_RevertWhen_SettleAfterDeadline() public {
        (bytes32 id, IIntentAuction.Intent memory i) = _postAndBid(2_000e6, 3e6);
        vm.roll(block.number + 11); // auction ended
        vm.warp(i.deadline + 1); // past user deadline
        vm.expectRevert(IIntentAuction.IntentExpired.selector);
        auction.settle(id);
    }

    function test_RevertWhen_SettleWithNoBid() public {
        IIntentAuction.Intent memory i = _intent(1 ether, 1_990e6, 5e6, 10);
        bytes memory sig = signIntent(userPk, address(auction), i);
        bytes32 id = auction.postIntent(i, sig);
        vm.roll(block.number + 11);
        vm.expectRevert(IIntentAuction.IntentNotSettleable.selector);
        auction.settle(id);
    }

    function test_RevertWhen_SettleTwice() public {
        (bytes32 id,) = _postAndBid(2_000e6, 3e6);
        vm.roll(block.number + 11);
        auction.settle(id);

        vm.expectRevert(IIntentAuction.IntentNotActive.selector);
        auction.settle(id);
    }

    // ----------------------------------------------------------------------
    // Executor griefing / slippage resistance
    // ----------------------------------------------------------------------

    function test_RevertWhen_SolverCalldataUnderdelivers() public {
        // Lower the DEX rate so the actual delivered amount falls below minDeliver.
        // Post a normal intent, bid committing to 2000 USDC — but rate only produces 1500.
        IIntentAuction.Intent memory i = _intent(1 ether, 1_490e6, 5e6, 10);
        bytes memory sig = signIntent(userPk, address(auction), i);
        bytes32 id = auction.postIntent(i, sig);

        bytes memory data = _encodeSwapCall(address(weth), address(usdc), 1 ether, address(executor));
        vm.prank(solver);
        auction.bidOnIntent(id, 2_000e6, 5e6, address(swap), data);

        // Now admin "rug-pulls" the rate before settlement (simulates: the mock DEX
        // returning less than the solver committed to).
        swap.setRate(address(weth), address(usdc), 1_500e6);

        vm.roll(block.number + 11);

        // Delivered = 1500e6, required minDeliver = 2000e6 → reverts.
        vm.expectRevert(
            abi.encodeWithSelector(IIntentAuction.DeliveredLessThanCommitted.selector, 2_000e6, 1_500e6)
        );
        auction.settle(id);

        // Most important assertion: user KEEPS their WETH. The settle revert rolls
        // back the transferFrom, which is the griefing-proof property.
        assertEq(weth.balanceOf(user), 10 ether, "user input tokens never lost");
        assertEq(usdc.balanceOf(user), 0, "user received nothing");
    }

    function test_Settle_OverDelivery_AllGoesToUser() public {
        // If the solver/router over-delivers (beneficial slippage), the USER captures
        // the upside — solver cannot pocket it.
        (bytes32 id,) = _postAndBid(1_990e6, 5e6); // solver commits to 1990, fee 5
        // Juice the rate — swap will deliver 2100 instead of 1990.
        swap.setRate(address(weth), address(usdc), 2_100e6);

        vm.roll(block.number + 11);
        auction.settle(id);

        // User expected 1985 (1990 - 5). They got 2100 - 5 = 2095.
        assertEq(usdc.balanceOf(user), 2_095e6, "user gets the over-delivery");
        assertEq(usdc.balanceOf(solver), 5e6, "solver only gets the committed fee");
    }

    function test_RevertWhen_ExecutorCalledDirectly() public {
        // The Executor's access control must block non-auction callers.
        Executor.FeeSplitParams memory p = Executor.FeeSplitParams({
            base: _dummyExecParams(),
            solverFee: 0
        });
        vm.expectRevert(Executor.NotAuction.selector);
        executor.executeWithFee(p);
    }

    // ----------------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------------

    function _intent(uint256 amountIn, uint256 minAmountOut, uint256 maxFee, uint256 dur)
        internal
        view
        returns (IIntentAuction.Intent memory)
    {
        return IIntentAuction.Intent({
            user: user,
            tokenIn: address(weth),
            amountIn: amountIn,
            tokenOut: address(usdc),
            minAmountOut: minAmountOut,
            maxSolverFee: maxFee,
            auctionDuration: dur,
            nonce: auction.nonces(user),
            deadline: block.timestamp + 1 hours
        });
    }

    function _postAndBid(uint256 outputOffered, uint256 solverFee)
        internal
        returns (bytes32 id, IIntentAuction.Intent memory i)
    {
        i = _intent(1 ether, 1_990e6, 5e6, 10);
        bytes memory sig = signIntent(userPk, address(auction), i);
        id = auction.postIntent(i, sig);

        bytes memory data = _encodeSwapCall(address(weth), address(usdc), 1 ether, address(executor));
        vm.prank(solver);
        auction.bidOnIntent(id, outputOffered, solverFee, address(swap), data);
    }

    function _encodeSwapCall(address tokenIn, address tokenOut, uint256 amountIn, address recipient)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(
            MockSwapRouter.swap.selector, tokenIn, tokenOut, amountIn, recipient
        );
    }

    function _dummyExecParams() internal view returns (IExecutor.ExecutionParams memory) {
        return IExecutor.ExecutionParams({
            intentId: bytes32(0),
            solver: solver,
            target: address(swap),
            data: hex"",
            tokenIn: address(weth),
            amountIn: 0,
            tokenOut: address(usdc),
            user: user,
            minDeliver: 0
        });
    }
}
