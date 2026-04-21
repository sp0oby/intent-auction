// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IIntentAuction} from "../../src/interfaces/IIntentAuction.sol";
import {IntentLib} from "../../src/libraries/IntentLib.sol";

/// @notice Shared helpers for building and signing Intent objects in tests.
/// @dev Foundry's `vm.sign(pk, digest)` produces the raw (v, r, s) tuple; we
///      repackage it as the 65-byte concatenated signature format that the
///      contract's SignatureChecker expects.
abstract contract SigUtils is Test {
    /// @dev Build an EIP-712 digest using the same domain as the live contract.
    function digestFor(address auction, IIntentAuction.Intent memory i)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = IntentLib.hashIntentMemory(i);
        // Reconstruct the domain separator the same way EIP712 does internally.
        bytes32 domainSeparator = _readDomainSeparator(auction);
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    /// @dev Exposes the contract's own DOMAIN_SEPARATOR so tests don't rebuild it
    ///      from scratch (and risk divergence with the production contract).
    function _readDomainSeparator(address auction) internal view returns (bytes32) {
        (bool ok, bytes memory ret) = auction.staticcall(abi.encodeWithSignature("DOMAIN_SEPARATOR()"));
        require(ok, "domain separator readable");
        return abi.decode(ret, (bytes32));
    }

    /// @dev Sign an intent as `pk` and return a 65-byte signature the contract accepts.
    function signIntent(uint256 pk, address auction, IIntentAuction.Intent memory i)
        internal
        view
        returns (bytes memory sig)
    {
        bytes32 digest = digestFor(auction, i);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        sig = abi.encodePacked(r, s, v);
    }
}
