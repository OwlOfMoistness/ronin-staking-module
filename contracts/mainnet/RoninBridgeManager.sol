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

enum ContractType {
  /*  0 */ UNKNOWN,
  /*  1 */ PAUSE_ENFORCER,
  /*  2 */ BRIDGE,
  /*  3 */ BRIDGE_TRACKING,
  /*  4 */ GOVERNANCE_ADMIN,
  /*  5 */ MAINTENANCE,
  /*  6 */ SLASH_INDICATOR,
  /*  7 */ STAKING_VESTING,
  /*  8 */ VALIDATOR,
  /*  9 */ STAKING,
  /* 10 */ RONIN_TRUSTED_ORGANIZATION,
  /* 11 */ BRIDGE_MANAGER,
  /* 12 */ BRIDGE_SLASH,
  /* 13 */ BRIDGE_REWARD,
  /* 14 */ FAST_FINALITY_TRACKING,
  /* 15 */ PROFILE
}

abstract contract RoninBridgeManager {
	address immutable public RONIN_BRIDGE;

	constructor(address _bridge) {
		RONIN_BRIDGE= _bridge;
	}

	function _getBridgeManager() internal view returns(address){
		return IRoninGateway(RONIN_BRIDGE).getContract(uint8(ContractType.BRIDGE_MANAGER));
	}

	/**  
	 * @notice
	 * Internal function that requests ether from the ronin bridge
	 * @param _amount Amount of ether to withdraw
	 */
	function _requestEtherFromBridge(uint256 _amount) internal {
		IRoninGateway(RONIN_BRIDGE).requestEther(_amount);
	}

	/**  
	 * @notice
	 * Internal function that pays back ether to the ronin bridge
	 * @param _amount Amount of ether to payback
	 */

	function _paybackBridge(uint256 _amount) internal {
		(bool res,) = RONIN_BRIDGE.call{value:_amount}("");
		if (!res) revert ErrRoninBridge();
	}
}