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

	/**  
	 * @notice
	 * Internal function that deposits ether from RETH tokens
	 * @param _amount Amount of ether to deposit
	 */
	function _stakeInRocketPool(uint256 _amount) internal {
		if (_amount > 0)
			IRocketDepositPool(RP_DEPOSIT_POOL).deposit{value:_amount}();
	}

	/**  
	 * @notice
	 * Internal function that withdraws ether from RETH tokens
	 * @param _amount Amount of ether to withdraw
	 */
	function _withdrawExactEthFromRocketPool(uint256 _amount) internal {
		if (_amount > 0) {
			uint256 rethToBurn = IRETH(RETH).getRethValue(_amount);
			IRETH(RETH).burn(rethToBurn);
		}
	}

	/**  
	 * @notice
	 * Internal function that withdraws ether from all RETH tokens the SEM holds
	 */
	function _exitFromRocketPool() internal {
		uint256 shares = IRETH(RETH).balanceOf(address(this));
		uint256 assets = IRETH(RETH).getEthValue(shares);
		uint256 maxWithdrawable = IRETH(RETH).getTotalCollateral();
		if (assets > maxWithdrawable)
			shares = IRETH(RETH).getRethValue(maxWithdrawable);
		IRETH(RETH).burn(shares);
	}
}