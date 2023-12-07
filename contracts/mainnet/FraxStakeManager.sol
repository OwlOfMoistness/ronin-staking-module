// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "../../interfaces/IFraxEthMinter.sol";
import "../../interfaces/IFraxRedemptionQueue.sol";
import "../../interfaces/ISfrxEth.sol";

abstract contract FraxStakeManager {
	address immutable public FRAX_MINTER;
	address immutable public FRAX_QUEUE;
	address immutable public SFRXETH;


	uint256 public fraxTotalWithdrawals;
	uint256 public fraxCurrentWithdrawalIndex;
	mapping(uint256 => uint256) public fraxWithdrawalList;

	event FraxWithdrawalRequests(uint256 nftId);

	constructor(address _fraxMinter, address _fraxQueue, address _sfrxEth) {
		FRAX_MINTER = _fraxMinter;
		FRAX_QUEUE = _fraxQueue;
		SFRXETH = _sfrxEth;
		ISfrxEth(SFRXETH).approve(FRAX_QUEUE, type(uint256).max);
	}

	function _stakeInFrax(uint256 _amount) internal {
		if (_amount > 0)
			IFraxEthMinter(FRAX_MINTER).submitAndDeposit{value:_amount}(address(this));
	}

	function _initiateWithdrawExactEthFromFrax(uint256 _amount) internal {
		if (_amount > 0) {
			uint256 sfrxEthAmountNeeded = ISfrxEth(SFRXETH).convertToShares(_amount);
			uint256 nftId = IFraxRedemptionQueue(FRAX_QUEUE).enterRedemptionQueueViaSfrxEth(address(this), uint120(sfrxEthAmountNeeded));
			fraxWithdrawalList[fraxTotalWithdrawals++] = nftId;
			emit FraxWithdrawalRequests(nftId);
		}
	}

	function _finaliseWithdrawExactEthFromFrax() internal returns(uint256 receivedEther) {
		uint256 nftId = fraxWithdrawalList[fraxCurrentWithdrawalIndex++];
		receivedEther = address(this).balance;
		IFraxRedemptionQueue(FRAX_QUEUE).burnRedemptionTicketNft(nftId, payable(address(this)));
		receivedEther = address(this).balance - receivedEther;
	}
}