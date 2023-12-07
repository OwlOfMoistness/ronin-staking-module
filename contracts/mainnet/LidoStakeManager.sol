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

	function _stakeInLido(uint256 _amount) internal {
		if (_amount > 0) {
			(bool res,) = wstETH.call{value:_amount}("");
			if (!res) revert ErrLidoStake();
		}
	}

	function _initiateWithdrawExactEthFromLido(uint256 _amount) internal {
		if (_amount > 0) {
			uint256 len = _amount / 1000 ether + (_amount % 1000 ether > 0 ? 1 : 0);
			uint256[] memory amounts = new uint256[](len);
			amounts[len - 1] = _amount % 1000 ether;
			for (uint256 i = 0; i < len - 1; i++)
				amounts[i] = 1000 ether;

			uint256 wstETHAmountToUnwrap = IwstETH(wstETH).getWstETHByStETH(_amount);
			IwstETH(wstETH).unwrap(wstETHAmountToUnwrap);
			uint256[] memory requestIds = IWithdrawalQueue(LIDO_QUEUE).requestWithdrawalsWstETH(amounts, address(this));
			lidoWithdrawalList[lidoTotalWithdrawals++] = LidoWithdrawal(_amount, requestIds);
			emit LidoWithdrawalRequests(requestIds);
		}
	}

	function _finaliseWithdrawExactEthFromLido() internal returns(uint256 receivedEther) {
		LidoWithdrawal memory withdrawal = lidoWithdrawalList[lidoCurrentWithdrawalIndex++];
		uint256[] memory hints = IWithdrawalQueue(LIDO_QUEUE).findCheckpointHints(
			withdrawal.requestIDs,
			1,
			IWithdrawalQueue(LIDO_QUEUE).getLastCheckpointIndex());
		receivedEther = address(this).balance;
		IWithdrawalQueue(LIDO_QUEUE).claimWithdrawals(withdrawal.requestIDs, hints);
		receivedEther = address(this).balance - receivedEther;
	}
}