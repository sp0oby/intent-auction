// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, Vm} from "forge-std/Test.sol";

import {IntentAuction} from "../src/IntentAuction.sol";
import {IIntentAuction} from "../src/interfaces/IIntentAuction.sol";
import {IntentLib} from "../src/libraries/IntentLib.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

import {SigUtils} from "./utils/SigUtils.sol";

/// @title IntentRegistry tests
/// @notice Covers EIP-712 signing, nonce handling, expiry, replay, cancellation.
contract IntentRegistryTest is SigUtils {
    IntentAuction internal auction;
    MockERC20 internal weth;
    MockERC20 internal usdc;

    uint256 internal userPk = 0xA11CE;
    address internal user;
    address internal admin = address(this);

    function setUp() public {
        user = vm.addr(userPk);
        auction = new IntentAuction(admin);
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
    }

    // ----------------------------------------------------------------------
    // Typehash safety — makes sure the typehash string stays in sync with the struct
    // ----------------------------------------------------------------------

    function test_TypehashMatchesExpectedString() public pure {
        // If the struct or string diverges, this test breaks immediately — loud, obvious.
        bytes32 expected = keccak256(
            "Intent(address user,address tokenIn,uint256 amountIn,address tokenOut,uint256 minAmountOut,uint256 maxSolverFee,uint256 auctionDuration,uint256 nonce,uint256 deadline)"
        );
        assertEq(IntentLib.INTENT_TYPEHASH, expected, "typehash drift");
    }

    // ----------------------------------------------------------------------
    // Happy path
    // ----------------------------------------------------------------------

    function test_PostIntent_HappyPath() public {
        IIntentAuction.Intent memory i = _buildIntent();
        bytes memory sig = signIntent(userPk, address(auction), i);

        vm.expectEmit(true, true, true, true);
        emit IIntentAuction.IntentPosted(
            _expectedId(i, sig),
            user,
            address(weth),
            address(usdc),
            i.amountIn,
            i.minAmountOut,
            uint96(block.number + i.auctionDuration)
        );

        bytes32 id = auction.postIntent(i, sig);

        assertEq(id, _expectedId(i, sig), "id mismatch");
        assertEq(auction.nonces(user), 1, "nonce bumped");
        IIntentAuction.AuctionState memory s = auction.getAuction(id);
        assertEq(s.intent.user, user);
        assertEq(s.auctionEndBlock, uint96(block.number + i.auctionDuration));
        assertEq(s.status, 0);
    }

    // ----------------------------------------------------------------------
    // Failure modes
    // ----------------------------------------------------------------------

    function test_RevertWhen_SignatureWrongSigner() public {
        IIntentAuction.Intent memory i = _buildIntent();
        // Sign with a DIFFERENT private key; the declared user is `user`.
        bytes memory badSig = signIntent(0xB0B, address(auction), i);

        vm.expectRevert(IIntentAuction.BadSignature.selector);
        auction.postIntent(i, badSig);
    }

    function test_RevertWhen_NonceStale() public {
        IIntentAuction.Intent memory i = _buildIntent();
        bytes memory sig = signIntent(userPk, address(auction), i);
        auction.postIntent(i, sig); // consumes nonce 0 → now 1

        // Replay the SAME intent with the SAME sig — nonce moved, must revert.
        vm.expectRevert(abi.encodeWithSelector(IIntentAuction.BadNonce.selector, 1, 0));
        auction.postIntent(i, sig);
    }

    function test_RevertWhen_Expired() public {
        IIntentAuction.Intent memory i = _buildIntent();
        i.deadline = block.timestamp; // strictly <= current time → expired
        bytes memory sig = signIntent(userPk, address(auction), i);

        vm.expectRevert(IIntentAuction.IntentExpired.selector);
        auction.postIntent(i, sig);
    }

    function test_RevertWhen_ZeroAmountIn() public {
        IIntentAuction.Intent memory i = _buildIntent();
        i.amountIn = 0;
        bytes memory sig = signIntent(userPk, address(auction), i);

        vm.expectRevert(IIntentAuction.InvalidAmount.selector);
        auction.postIntent(i, sig);
    }

    function test_RevertWhen_MaxFeeExceedsMinOut() public {
        IIntentAuction.Intent memory i = _buildIntent();
        i.maxSolverFee = i.minAmountOut; // equal is not allowed
        bytes memory sig = signIntent(userPk, address(auction), i);

        vm.expectRevert(IIntentAuction.InvalidAmount.selector);
        auction.postIntent(i, sig);
    }

    function test_RevertWhen_CrossContractReplay() public {
        // Simulate: same typed data, but signed for a different auction contract
        // (different domain separator). MUST fail — this is the canonical replay
        // protection EIP-712 exists to provide.
        IntentAuction otherAuction = new IntentAuction(admin);
        IIntentAuction.Intent memory i = _buildIntent();
        bytes memory sig = signIntent(userPk, address(otherAuction), i);

        vm.expectRevert(IIntentAuction.BadSignature.selector);
        auction.postIntent(i, sig);
    }

    function test_CancelIntent_ByUser() public {
        IIntentAuction.Intent memory i = _buildIntent();
        bytes memory sig = signIntent(userPk, address(auction), i);
        bytes32 id = auction.postIntent(i, sig);

        vm.expectEmit(true, true, true, true);
        emit IIntentAuction.IntentCancelled(id, user);

        vm.prank(user);
        auction.cancelIntent(id);

        IIntentAuction.AuctionState memory s = auction.getAuction(id);
        assertEq(s.status, 2, "cancelled flag");
    }

    function test_RevertWhen_CancelByNonOwner() public {
        IIntentAuction.Intent memory i = _buildIntent();
        bytes memory sig = signIntent(userPk, address(auction), i);
        bytes32 id = auction.postIntent(i, sig);

        vm.expectRevert(IIntentAuction.NotIntentOwner.selector);
        auction.cancelIntent(id); // called by test contract, not `user`
    }

    function test_IncreaseNonce_InvalidatesSignatures() public {
        // Sign with nonce 0.
        IIntentAuction.Intent memory i = _buildIntent();
        bytes memory sig = signIntent(userPk, address(auction), i);

        // User bumps nonce to 1. The pre-signed intent now has the wrong nonce.
        vm.prank(user);
        auction.increaseNonce();

        vm.expectRevert(abi.encodeWithSelector(IIntentAuction.BadNonce.selector, 1, 0));
        auction.postIntent(i, sig);
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
            minAmountOut: 1900e6,
            maxSolverFee: 10e6,
            auctionDuration: 10,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });
    }

    function _expectedId(IIntentAuction.Intent memory i, bytes memory sig)
        internal
        view
        returns (bytes32)
    {
        return IntentLib.intentId(digestFor(address(auction), i), sig);
    }
}
