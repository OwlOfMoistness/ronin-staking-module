// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "../../interfaces/IRETH.sol";
import "../../interfaces/IRocketDepositPool.sol";

abstract contract RocketPoolStakeManager {

	address immutable public RETH;
	address immutable public RP_DEPOSIT_POOL;

	constructor(address _reth, address _pool) {
		RETH = _reth;
		RP_DEPOSIT_POOL = _pool;
	}


	function _stakeInRocketPool(uint256 _amount) internal {
		if (_amount > 0)
			IRocketDepositPool(RP_DEPOSIT_POOL).deposit{value:_amount}();
	}

	function _withdrawExactEthFromRocketPool(uint256 _amount) internal {
		if (_amount > 0) {
			uint256 rethToBurn = IRETH(RETH).getRethValue(_amount);
			IRETH(RETH).burn(rethToBurn);
		}
	}
}