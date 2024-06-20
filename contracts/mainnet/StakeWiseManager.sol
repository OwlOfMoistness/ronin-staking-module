// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "../../interfaces/IStakeWise.sol";

abstract contract StakeWiseManager {
	IStakeWise public immutable vault;

	event StakeWiseExitInitiated(uint256 ticket, uint256 timestamp, int256 queueIndex);

	constructor(address _swVault) {
		vault = IStakeWise(_swVault);
	}

	/**
	 * @notice
	 * Internal function that returns the total amount of assets staked in the vault
	 * @return Total amount of assets staked in the vault
	 */
	function _totalStaked() internal view returns (uint256) {
		return vault.totalAssets();
	}

	/**
	 * @notice
	 * Internal function that deposits ether in the StakeWise vault
	 * @param _amount Amount of ether to deposit
	 */
	function _stakeInStakeWise(uint256 _amount) internal {
		if (_amount == 0) return;
		vault.deposit{value:_amount}(address(this), address(0));
	}

	/**
	 * @notice
	 * Internal function that instantly withdraws ether from the StakeWise vault
	 * @param _amount Amount of ether to withdraw
	 */
	function _withdrawExactEthFromStakeWise(uint256 _amount) internal {
		if (_amount == 0) return;
		uint256 assets = vault.convertToAssets(_amount);
		vault.redeem(assets, address(this));
	}

	/**
	 * @notice
	 * Internal function that initiates a withdrawal request to the StakeWise vault
	 * @param _amount Amount of ether to withdraw
	 */
	function _withdrawInitQueueStakeWise(uint256 _amount) internal {
		if (_amount == 0) return;
		uint256 shares;
		if (_amount == type(uint256).max)
			shares = vault.getShares(address(this));
		else
			shares = vault.convertToAssets(_amount);
		uint256 ticketId = vault.enterExitQueue(shares, address(this));
		int256 queueIndex = vault.getExitQueueIndex(ticketId);
		emit StakeWiseExitInitiated(ticketId, block.timestamp, queueIndex);
	}

	/**
	 * @notice
	 * Internal function that finalises a withdrawal request from the StakeWise vault
	 * @param _ticket Ticket ID of the withdrawal request
	 * @param _timestamp Timestamp of the withdrawal request
	 * @param _queueIndex Index of the withdrawal request in the queue
	 */
	function _withdrawExitQueueStakeWise(uint256 _ticket, uint256 _timestamp, uint256 _queueIndex) internal {
		(uint256 newPositionTicket,,) = vault.claimExitedAssets(_ticket, _timestamp, _queueIndex);
		if (newPositionTicket != 0) {
			int256 queueIndex = vault.getExitQueueIndex(newPositionTicket);
			emit StakeWiseExitInitiated(newPositionTicket, block.timestamp, queueIndex);
		}
	}
}