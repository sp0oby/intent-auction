// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IntentAuction} from "../../src/IntentAuction.sol";
import {Executor} from "../../src/Executor.sol";
import {IIntentAuction} from "../../src/interfaces/IIntentAuction.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockSwapRouter} from "../../src/mocks/MockSwapRouter.sol";

import {SigUtils} from "./SigUtils.sol";

/// @title Handler
/// @notice Bounded random-action driver for invariant testing.
/// @dev Foundry's `targetContract` system will call the public/external functions of
///      this handler with random arguments; we translate them into plausible protocol
///      actions (post, bid, settle, cancel, timeWarp). The handler carries the state
///      needed to keep those actions coherent (tracked intent ids, user nonces, etc.).
contract Handler is SigUtils {
    IntentAuction public auction;
    Executor public executor;
    MockERC20 public weth;
    MockERC20 public usdc;
    MockSwapRouter public swap;

    // Deterministic users + their private keys.
    uint256 internal constant NUM_USERS = 3;
    uint256[NUM_USERS] internal userPks;
    address[NUM_USERS] internal users;

    bytes32[] public intentIds;
    mapping(bytes32 => bool) public seen;

    // Running ghost variables — assertions in the invariant_* methods read these.
    uint256 public ghostTotalIntentInAmount; // sum of amountIn for every posted intent
    uint256 public ghostTotalSettled; // count of successful settlements
    uint256 public ghostLastMaxNonce; // max nonce ever observed (monotonicity helper)

    constructor(IntentAuction _auction, MockERC20 _weth, MockERC20 _usdc, MockSwapRouter _swap) {
        auction = _auction;
        executor = _auction.executor();
        weth = _weth;
        usdc = _usdc;
        swap = _swap;

        userPks[0] = 0xA11CE;
        userPks[1] = 0xB0B;
        userPks[2] = 0xCA11ED;
        for (uint256 i; i < NUM_USERS; i++) {
            users[i] = vm.addr(userPks[i]);
            weth.mint(users[i], 1_000_000 ether);
            vm.prank(users[i]);
            weth.approve(address(auction), type(uint256).max);
        }
    }

    // ----------------------------------------------------------------------
    // Random actions
    // ----------------------------------------------------------------------

    function postRandom(uint256 userSeed, uint256 amountIn, uint256 minOut, uint256 maxFee) external {
        uint256 uIdx = userSeed % NUM_USERS;
        address u = users[uIdx];

        amountIn = bound(amountIn, 1e15, 50 ether);
        minOut = bound(minOut, 10e6, 200_000e6);
        // Fee cap strictly less than floor — required by intent validation.
        if (minOut <= 1) return;
        maxFee = bound(maxFee, 0, minOut - 1);

        IIntentAuction.Intent memory i = IIntentAuction.Intent({
            user: u,
            tokenIn: address(weth),
            amountIn: amountIn,
            tokenOut: address(usdc),
            minAmountOut: minOut,
            maxSolverFee: maxFee,
            auctionDuration: 5,
            nonce: auction.nonces(u),
            deadline: block.timestamp + 1 hours
        });
        bytes memory sig = signIntent(userPks[uIdx], address(auction), i);
        try auction.postIntent(i, sig) returns (bytes32 id) {
            intentIds.push(id);
            seen[id] = true;
            ghostTotalIntentInAmount += amountIn;
            uint256 n = auction.nonces(u);
            if (n > ghostLastMaxNonce) ghostLastMaxNonce = n;
        } catch {}
    }

    function bidRandom(uint256 idSeed, uint256 solverSeed, uint256 output, uint256 fee) external {
        if (intentIds.length == 0) return;
        bytes32 id = intentIds[idSeed % intentIds.length];
        IIntentAuction.AuctionState memory s = auction.getAuction(id);
        if (s.status != 0) return;
        if (block.number > s.auctionEndBlock) return;

        output = bound(output, s.intent.minAmountOut, s.intent.minAmountOut * 3 + 1);
        fee = bound(fee, 0, s.intent.maxSolverFee);
        if (fee >= output) return;

        // Set a rate that matches (or over-delivers) the bid output so settlement succeeds.
        // rate = output * 1e18 / amountIn, rounded up.
        uint256 rate = (output * 1e18 + s.intent.amountIn - 1) / s.intent.amountIn;
        swap.setRate(address(weth), address(usdc), rate);

        address solver = address(uint160(uint256(keccak256(abi.encode("solver", solverSeed)))));
        bytes memory data = abi.encodeWithSelector(
            MockSwapRouter.swap.selector, address(weth), address(usdc), s.intent.amountIn, address(executor)
        );
        vm.prank(solver);
        try auction.bidOnIntent(id, output, fee, address(swap), data) {} catch {}
    }

    function settleRandom(uint256 idSeed) external {
        if (intentIds.length == 0) return;
        bytes32 id = intentIds[idSeed % intentIds.length];
        IIntentAuction.AuctionState memory s = auction.getAuction(id);
        if (s.status != 0) return;
        if (block.number <= s.auctionEndBlock) return;
        if (s.winningBid.solver == address(0)) return;

        try auction.settle(id) {
            ghostTotalSettled += 1;
        } catch {}
    }

    function cancelRandom(uint256 idSeed) external {
        if (intentIds.length == 0) return;
        bytes32 id = intentIds[idSeed % intentIds.length];
        IIntentAuction.AuctionState memory s = auction.getAuction(id);
        if (s.status != 0) return;

        vm.prank(s.intent.user);
        try auction.cancelIntent(id) {} catch {}
    }

    function timeWarp(uint256 blocks_) external {
        blocks_ = bound(blocks_, 1, 20);
        vm.roll(block.number + blocks_);
    }

    // ----------------------------------------------------------------------
    // Introspection helpers for the invariant contract
    // ----------------------------------------------------------------------

    function numIntents() external view returns (uint256) {
        return intentIds.length;
    }

    function intentAt(uint256 i) external view returns (bytes32) {
        return intentIds[i];
    }

    function userAt(uint256 i) external view returns (address) {
        return users[i % NUM_USERS];
    }
}
