// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "../../interfaces/IRoninGateway.sol";

error ErrRoninBridge();

abstract contract RoninBridgeManager {
	address immutable public RONIN_BRIDGE;

	constructor(address _bridge) {
		RONIN_BRIDGE= _bridge;
	}

	function _requestEtherFromBridge(uint256 _amount) internal {
		IRoninGateway(RONIN_BRIDGE).requestEther(_amount);
	}

	function _paybackBridge(uint256 _amount) internal {
		(bool res,) = RONIN_BRIDGE.call{value:_amount}("");
		if (!res) revert ErrRoninBridge();
	}
}