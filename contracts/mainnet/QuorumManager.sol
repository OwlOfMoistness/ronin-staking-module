// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "@openzeppelin/utils/cryptography/ECDSA.sol";
import "../../interfaces/IBridgeManager.sol";
import "../../interfaces/IRoninGateway.sol";

error ErrConsumedHash();
error ErrInvalidOrder();
error ErrQueryForInsufficientVoteWeight();

abstract contract QuorumManager {
	using ECDSA for bytes32;

	mapping(bytes32 => bool) public consumedHashes;

	function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
		return
			keccak256(
				abi.encode(
					// keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)')
					0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
					// keccak256("StakedEtherManager")
					0xcb49bd38ba2973d9b0a664529fe2e40e4f8b12f547bc96eb4c79165cb3d9371c,
					// keccak256("1")
					0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6,
					block.chainid,
					address(this)
				)
			);
    }

	function _validateSignatures(address _value, uint256 counter, bytes32 _variableSig, address _bridgeManager, IRoninGateway.Signature[] memory _signatures) internal {
		bytes32 valueHash = keccak256(abi.encodePacked(_value, counter, _variableSig));
		bytes32 digest = _valueDigest(DOMAIN_SEPARATOR(), valueHash);
		uint256 minimumVoteWeight = _getTotalWeight(_bridgeManager) * 70 / 100;
		
		if (consumedHashes[valueHash]) revert ErrConsumedHash();
		{
			bool _passed;
			address _signer;
			address _lastSigner;
			IRoninGateway.Signature memory _sig;
			uint256 _weight;
			for (uint256 _i; _i < _signatures.length; ) {
				_sig = _signatures[_i];
				_signer = ecrecover(digest, _sig.v, _sig.r, _sig.s);
				if (_lastSigner >= _signer) revert ErrInvalidOrder();

				_lastSigner = _signer;

				_weight += _getWeight(_signer, _bridgeManager);
				if (_weight >= minimumVoteWeight) {
					_passed = true;
					break;
				}

				unchecked {
					++_i;
				}
			}

			if (!_passed) revert ErrQueryForInsufficientVoteWeight();
			consumedHashes[valueHash] = true;
		}
	}

	function _getWeight(address _addr, address _bridgeManager) internal view returns (uint256) {
		return IBridgeManager(_bridgeManager).getBridgeOperatorWeight(_addr);
	}

	function _getTotalWeight(address _bridgeManager) internal view returns (uint256) {
		return IBridgeManager(_bridgeManager).getTotalWeight();
	}

	function _valueDigest(bytes32 _domainSeparator, bytes32 _valueHash) internal pure returns(bytes32) {
		return _domainSeparator.toTypedDataHash(_valueHash);
	}
}