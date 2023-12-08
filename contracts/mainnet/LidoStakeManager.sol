// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "../../interfaces/IwstETH.sol";
import "../../interfaces/ILido.sol";
import "../../interfaces/ILidoWithdrawalQueue.sol";

error ErrLidoStake();

abstract contract LidoStakeManager {
	struct LidoWithdrawal {
		uint256 amount;
		uint256[] requestIDs;
	}

	address immutable public wstETH;
	address immutable public stETH;
	address immutable public LIDO_QUEUE;

	uint256 public lidoTotalWithdrawals;
	uint256 public lidoCurrentWithdrawalIndex;
	mapping(uint256 => LidoWithdrawal) public lidoWithdrawalList;


	event LidoWithdrawalRequests(uint256[] requests);

	constructor(address _wsteth, address _steth, address _queue) {
		wstETH = _wsteth;
		stETH = _steth;
		LIDO_QUEUE = _queue;
	}

	/**  
	 * @notice
	 * Internal function that deposits ether for wstETH tokens
	 * @param _amount Amount of ether to deposit
	 */
	function _stakeInLido(uint256 _amount) internal {
		if (_amount > 0) {
			(bool res,) = wstETH.call{value:_amount}("");
			if (!res) revert ErrLidoStake();
		}
	}

	/**  
	 * @notice
	 * Internal function that initiates a lido withdrawal. An nft will be minted on the SEM to be burnt later in exchange of ether
	 * @param _amount Amount of ether to withdraw
	 */
	function _initiateWithdrawExactEthFromLido(uint256 _amount) internal {
		if (_amount > 0) {
			uint256 len = _amount / 1000 ether + (_amount % 1000 ether > 0 ? 1 : 0);
			uint256[] memory amounts = new uint256[](len);
			amounts[len - 1] = _amount % 1000 ether;
			for (uint256 i = 0; i < len - 1; i++)
				amounts[i] = 1000 ether;

			uint256 wstETHAmountToUnwrap = IwstETH(wstETH).getWstETHByStETH(_amount);
			IwstETH(wstETH).approve(LIDO_QUEUE, wstETHAmountToUnwrap);
			// todo make sure this is correct
			uint256[] memory requestIds = IWithdrawalQueue(LIDO_QUEUE).requestWithdrawalsWstETH(amounts, address(this));
			lidoWithdrawalList[lidoTotalWithdrawals++] = LidoWithdrawal(_amount, requestIds);
			emit LidoWithdrawalRequests(requestIds);
		}
	}

	/**  
	 * @notice
	 * Internal function that finalises a lido withdrawal. Previously obtained NFT will be consumed in exchange of ether
	 * @return receivedEther Amount of received ether
	 */
	function _finaliseWithdrawExactEthFromLido() internal returns(uint256 receivedEther) {
		if (lidoCurrentWithdrawalIndex == lidoTotalWithdrawals) return 0;
		LidoWithdrawal memory withdrawal = lidoWithdrawalList[lidoCurrentWithdrawalIndex++];
		uint256[] memory hints = IWithdrawalQueue(LIDO_QUEUE).findCheckpointHints(
			withdrawal.requestIDs,
			1,
			IWithdrawalQueue(LIDO_QUEUE).getLastCheckpointIndex());
		receivedEther = address(this).balance;
		IWithdrawalQueue(LIDO_QUEUE).claimWithdrawals(withdrawal.requestIDs, hints);
		receivedEther = address(this).balance - receivedEther;
	}

	/**  
	 * @notice
	 * Internal function that initiates a full lido withdrawal. An nft will be minted on the SEM to be burnt later in exchange of ether
	 */
	function _initiateExitFromLido() internal {
		uint256 shares = IwstETH(wstETH).balanceOf(address(this));
		uint256 assets = IwstETH(wstETH).getStETHByWstETH(shares);

		if (assets > 0) {
			uint256 len = assets / 1000 ether + (assets % 1000 ether > 0 ? 1 : 0);
			uint256[] memory amounts = new uint256[](len);
			amounts[len - 1] = assets % 1000 ether;
			for (uint256 i = 0; i < len - 1; i++)
				amounts[i] = 1000 ether;

			uint256 wstETHAmountToUnwrap = IwstETH(wstETH).getWstETHByStETH(assets);
			IwstETH(wstETH).approve(LIDO_QUEUE, wstETHAmountToUnwrap);
			uint256[] memory requestIds = IWithdrawalQueue(LIDO_QUEUE).requestWithdrawalsWstETH(amounts, address(this));
			lidoWithdrawalList[lidoTotalWithdrawals++] = LidoWithdrawal(assets, requestIds);
			emit LidoWithdrawalRequests(requestIds);
		}
	}

	/**  
	 * @notice
	 * Internal function that finalises a full lido withdrawal. Previously obtained NFT will be consumed in exchange of ether
	 */
	function _finaliseExitFromLido(uint256 _index) internal {
		LidoWithdrawal memory withdrawal = lidoWithdrawalList[_index];
		uint256[] memory hints = IWithdrawalQueue(LIDO_QUEUE).findCheckpointHints(
			withdrawal.requestIDs,
			1,
			IWithdrawalQueue(LIDO_QUEUE).getLastCheckpointIndex());
		IWithdrawalQueue(LIDO_QUEUE).claimWithdrawals(withdrawal.requestIDs, hints);
	}
}