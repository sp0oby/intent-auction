// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IntentAuction} from "../src/IntentAuction.sol";
import {IIntentAuction} from "../src/interfaces/IIntentAuction.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

import {SigUtils} from "./utils/SigUtils.sol";

/// @title SolverAuction tests
/// @notice Covers bid ordering, auction window, target whitelist, griefing bounds.
contract SolverAuctionTest is SigUtils {
    IntentAuction internal auction;
    MockERC20 internal weth;
    MockERC20 internal usdc;

    uint256 internal userPk = 0xA11CE;
    address internal user;
    address internal admin = address(this);
    address internal target = makeAddr("whitelistedTarget");
    address internal solverA = makeAddr("solverA");
    address internal solverB = makeAddr("solverB");

    bytes32 internal id;

    function setUp() public {
        user = vm.addr(userPk);
        auction = new IntentAuction(admin);
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        auction.setTargetAllowed(target, true);

        IIntentAuction.Intent memory i = _buildIntent();
        bytes memory sig = signIntent(userPk, address(auction), i);
        id = auction.postIntent(i, sig);
    }

    // ----------------------------------------------------------------------
    // Happy path + ordering
    // ----------------------------------------------------------------------

    function test_FirstValidBidBecomesWinner() public {
        vm.prank(solverA);
        auction.bidOnIntent(id, 2_000e6, 5e6, target, hex"");

        IIntentAuction.AuctionState memory s = auction.getAuction(id);
        assertEq(s.winningBid.solver, solverA);
        assertEq(s.winningBid.outputOffered, 2_000e6);
        assertEq(s.winningBid.solverFee, 5e6);
    }

    function test_HigherNetValueWins() public {
        vm.prank(solverA);
        auction.bidOnIntent(id, 2_000e6, 5e6, target, hex""); // net 1995e6

        // solverB offers less output but lower fee → net 1996e6 > 1995e6 → wins.
        vm.prank(solverB);
        auction.bidOnIntent(id, 1_998e6, 2e6, target, hex"");

        IIntentAuction.AuctionState memory s = auction.getAuction(id);
        assertEq(s.winningBid.solver, solverB, "B should win on net value");
    }

    function test_RevertWhen_BidIsNotStrictImprovement() public {
        vm.prank(solverA);
        auction.bidOnIntent(id, 2_000e6, 5e6, target, hex""); // net 1995e6

        // Tie (same net value) must revert — strict improvement required.
        vm.prank(solverB);
        vm.expectRevert(IIntentAuction.BidNotAnImprovement.selector);
        auction.bidOnIntent(id, 2_000e6, 5e6, target, hex"");
    }

    function test_RevertWhen_OutputBelowMin() public {
        vm.prank(solverA);
        vm.expectRevert(IIntentAuction.BidBelowMin.selector);
        auction.bidOnIntent(id, 1_899e6, 1, target, hex""); // < minAmountOut of 1900e6
    }

    function test_RevertWhen_FeeAboveCap() public {
        vm.prank(solverA);
        vm.expectRevert(IIntentAuction.FeeExceedsMax.selector);
        auction.bidOnIntent(id, 2_000e6, 11e6, target, hex""); // maxSolverFee is 10e6
    }

    function test_RevertWhen_TargetNotWhitelisted() public {
        address notWhitelisted = makeAddr("random");
        vm.prank(solverA);
        vm.expectRevert(abi.encodeWithSelector(IIntentAuction.TargetNotAllowed.selector, notWhitelisted));
        auction.bidOnIntent(id, 2_000e6, 5e6, notWhitelisted, hex"");
    }

    function test_RevertWhen_TargetIsAuctionItself() public {
        auction.setTargetAllowed(address(auction), true); // admin mistake / misconfig
        vm.prank(solverA);
        vm.expectRevert(IIntentAuction.SelfCallForbidden.selector);
        auction.bidOnIntent(id, 2_000e6, 5e6, address(auction), hex"");
    }

    function test_RevertWhen_AuctionEnded() public {
        vm.roll(block.number + 11); // pass the 10-block window
        vm.prank(solverA);
        vm.expectRevert(IIntentAuction.AuctionEnded.selector);
        auction.bidOnIntent(id, 2_000e6, 5e6, target, hex"");
    }

    function test_RevertWhen_IntentCancelled() public {
        vm.prank(user);
        auction.cancelIntent(id);
        vm.prank(solverA);
        vm.expectRevert(IIntentAuction.IntentNotActive.selector);
        auction.bidOnIntent(id, 2_000e6, 5e6, target, hex"");
    }

    function test_RevertWhen_NonAdminTogglesTarget() public {
        address rando = makeAddr("rando");
        vm.prank(rando);
        vm.expectRevert();
        auction.setTargetAllowed(target, false);
    }

    // ----------------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------------

    function _buildIntent() internal view returns (IIntentAuction.Intent memory) {
        return IIntentAuction.Intent({
            user: user,
            tokenIn: address(weth),
            amountIn: 1 ether,
            tokenOut: address(usdc),
            minAmountOut: 1_900e6,
            maxSolverFee: 10e6,
            auctionDuration: 10,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });
    }
}
