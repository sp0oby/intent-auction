// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IntentAuction} from "../src/IntentAuction.sol";
import {Executor} from "../src/Executor.sol";
import {IIntentAuction} from "../src/interfaces/IIntentAuction.sol";
import {IntentLib} from "../src/libraries/IntentLib.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockSwapRouter} from "../src/mocks/MockSwapRouter.sol";

import {SigUtils} from "./utils/SigUtils.sol";

/// @title IntentAuction fuzz tests
/// @notice Property-based coverage for three high-value properties:
///           1. Net-value ordering: the leading bid always has the strictly highest
///              `outputOffered - solverFee` seen so far.
///           2. Settlement never leaves the user worse off than the signed floor.
///           3. EIP-712 hashing is collision-free: two distinct Intents must hash differently.
///
/// @dev Each test uses `bound()` to keep inputs within sensible ranges (no overflow,
///      no pathological values). Foundry's default is 1000 runs; `foundry.toml`
///      boosts this, and `forge test --fuzz-runs 10000` hammers them harder in CI.
contract IntentAuctionFuzzTest is SigUtils {
    IntentAuction internal auction;
    Executor internal executor;
    MockERC20 internal weth;
    MockERC20 internal usdc;
    MockSwapRouter internal swap;

    uint256 internal userPk = 0xA11CE;
    address internal user;
    address internal admin = address(this);

    uint256 internal constant MAX_AMOUNT_IN = 1_000 ether;
    uint256 internal constant MAX_OUTPUT = 10_000_000e6;

    function setUp() public {
        user = vm.addr(userPk);
        auction = new IntentAuction(admin);
        executor = auction.executor();
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        swap = new MockSwapRouter();
        auction.setTargetAllowed(address(swap), true);

        // Seed user with lots of WETH and pre-approve auction.
        weth.mint(user, 1_000_000 ether);
        vm.prank(user);
        weth.approve(address(auction), type(uint256).max);
    }

    // ----------------------------------------------------------------------
    // Property 1 — net-value ordering
    // ----------------------------------------------------------------------

    /// @dev If we place two bids where bid2 has STRICTLY higher net value than bid1,
    ///      bid2 MUST become the winner. If bid2's net value is <= bid1's, the second
    ///      call MUST revert (strict-improvement rule) and bid1 remains the winner.
    function testFuzz_NetValueOrdering(uint256 output1, uint256 fee1, uint256 output2, uint256 fee2)
        public
    {
        // Bound to non-degenerate ranges. minAmountOut = 1000e6; maxFee = 100e6.
        uint256 minAmountOut = 1_000e6;
        uint256 maxFee = 100e6;

        output1 = bound(output1, minAmountOut, MAX_OUTPUT);
        fee1 = bound(fee1, 0, maxFee);
        vm.assume(fee1 < output1); // enforce bidOnIntent's FeeExceedsOutput precondition
        output2 = bound(output2, minAmountOut, MAX_OUTPUT);
        fee2 = bound(fee2, 0, maxFee);
        vm.assume(fee2 < output2);

        bytes32 id = _postIntent(minAmountOut, maxFee);

        address solverA = makeAddr("A");
        address solverB = makeAddr("B");

        // First bid always lands (it's the first).
        vm.prank(solverA);
        auction.bidOnIntent(id, output1, fee1, address(swap), hex"");

        uint256 net1 = output1 - fee1;
        uint256 net2 = output2 - fee2;

        if (net2 > net1) {
            vm.prank(solverB);
            auction.bidOnIntent(id, output2, fee2, address(swap), hex"");

            IIntentAuction.AuctionState memory s = auction.getAuction(id);
            assertEq(s.winningBid.solver, solverB, "higher net value must win");
            assertEq(s.winningBid.outputOffered, output2);
            assertEq(s.winningBid.solverFee, fee2);
        } else {
            vm.prank(solverB);
            vm.expectRevert(IIntentAuction.BidNotAnImprovement.selector);
            auction.bidOnIntent(id, output2, fee2, address(swap), hex"");

            IIntentAuction.AuctionState memory s = auction.getAuction(id);
            assertEq(s.winningBid.solver, solverA, "first bidder retained");
        }
    }

    // ----------------------------------------------------------------------
    // Property 2 — settlement never leaves the user below their floor
    // ----------------------------------------------------------------------

    /// @dev For any valid bid that settles, the user's tokenOut receipt is >= minAmountOut
    ///      AND the user's tokenIn balance decreased by exactly amountIn.
    function testFuzz_SettleNeverLosesUserFunds(
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 maxFee,
        uint256 rate,
        uint256 solverFee
    ) public {
        FuzzInputs memory f = _prepFuzzInputs(amountIn, minAmountOut, maxFee, rate, solverFee);
        _runSettleFuzz(f);
    }

    struct FuzzInputs {
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 maxFee;
        uint256 rate;
        uint256 solverFee;
        uint256 expectedDelivered;
    }

    function _prepFuzzInputs(
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 maxFee,
        uint256 rate,
        uint256 solverFee
    ) internal returns (FuzzInputs memory f) {
        f.amountIn = bound(amountIn, 1e15, 100 ether); // 0.001 to 100 WETH
        f.minAmountOut = bound(minAmountOut, 100e6, 1_000_000e6);
        f.maxFee = bound(maxFee, 0, f.minAmountOut / 10);
        vm.assume(f.maxFee < f.minAmountOut);

        uint256 minRate = (f.minAmountOut * 1e18) / f.amountIn + 1;
        f.rate = bound(rate, minRate, minRate * 10);
        f.solverFee = bound(solverFee, 0, f.maxFee);

        swap.setRate(address(weth), address(usdc), f.rate);
        f.expectedDelivered = (f.amountIn * f.rate) / 1e18;

        vm.assume(f.solverFee < f.expectedDelivered);
        vm.assume(f.expectedDelivered - f.solverFee >= f.minAmountOut);
    }

    function _runSettleFuzz(FuzzInputs memory f) internal {
        IIntentAuction.Intent memory i = IIntentAuction.Intent({
            user: user,
            tokenIn: address(weth),
            amountIn: f.amountIn,
            tokenOut: address(usdc),
            minAmountOut: f.minAmountOut,
            maxSolverFee: f.maxFee,
            auctionDuration: 5,
            nonce: auction.nonces(user),
            deadline: block.timestamp + 1 hours
        });
        bytes memory sig = signIntent(userPk, address(auction), i);
        bytes32 id = auction.postIntent(i, sig);

        address solver = makeAddr("solver_fuzz");
        vm.prank(solver);
        auction.bidOnIntent(
            id,
            f.expectedDelivered,
            f.solverFee,
            address(swap),
            abi.encodeWithSelector(
                MockSwapRouter.swap.selector,
                address(weth),
                address(usdc),
                f.amountIn,
                address(executor)
            )
        );

        uint256 userWethBefore = weth.balanceOf(user);
        vm.roll(block.number + 6);
        auction.settle(id);

        assertGe(usdc.balanceOf(user), f.minAmountOut, "user got at least minAmountOut");
        assertEq(userWethBefore - weth.balanceOf(user), f.amountIn, "exactly amountIn consumed");
        assertEq(usdc.balanceOf(solver), f.solverFee, "solver got exactly their fee");
        assertEq(weth.balanceOf(address(executor)), 0, "no executor residual weth");
        assertEq(usdc.balanceOf(address(executor)), 0, "no executor residual usdc");
    }

    // ----------------------------------------------------------------------
    // Property 3 — EIP-712 hashing collision resistance
    // ----------------------------------------------------------------------

    /// @dev Two intents that differ in ANY field MUST produce different digests.
    function testFuzz_DigestCollisionResistance(
        IIntentAuction.Intent memory a,
        IIntentAuction.Intent memory b
    ) public view {
        // The only legitimate way to collide is if every field is equal. We don't want to
        // spend a fuzz run on that — skip it (astronomical odds by construction anyway).
        vm.assume(
            a.user != b.user || a.tokenIn != b.tokenIn || a.amountIn != b.amountIn
                || a.tokenOut != b.tokenOut || a.minAmountOut != b.minAmountOut
                || a.maxSolverFee != b.maxSolverFee || a.auctionDuration != b.auctionDuration
                || a.nonce != b.nonce || a.deadline != b.deadline
        );

        bytes32 ha = IntentLib.hashIntentMemory(a);
        bytes32 hb = IntentLib.hashIntentMemory(b);
        assertTrue(ha != hb, "distinct intents must hash differently");
    }

    // ----------------------------------------------------------------------
    // Helper
    // ----------------------------------------------------------------------

    function _postIntent(uint256 minAmountOut, uint256 maxFee) internal returns (bytes32 id) {
        IIntentAuction.Intent memory i = IIntentAuction.Intent({
            user: user,
            tokenIn: address(weth),
            amountIn: 1 ether,
            tokenOut: address(usdc),
            minAmountOut: minAmountOut,
            maxSolverFee: maxFee,
            auctionDuration: 10,
            nonce: auction.nonces(user),
            deadline: block.timestamp + 1 hours
        });
        bytes memory sig = signIntent(userPk, address(auction), i);
        id = auction.postIntent(i, sig);
    }
}
