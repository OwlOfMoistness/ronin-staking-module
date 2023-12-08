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


	/**  
	 * @notice
	 * Internal function that deposits ether from sfrxETH tokens
	 * @param _amount Amount of ether to deposit
	 */
	function _stakeInFrax(uint256 _amount) internal {
		if (_amount > 0)
			IFraxEthMinter(FRAX_MINTER).submitAndDeposit{value:_amount}(address(this));
	}

	/**  
	 * @notice
	 * Internal function that initiates a frax withdrawal. An nft will be minted on the SEM to be burnt later in exchange of ether
	 * @param _amount Amount of ether to withdraw
	 */
	function _initiateWithdrawExactEthFromFrax(uint256 _amount) internal {
		if (_amount > 0) {
			uint256 sfrxEthAmountNeeded = ISfrxEth(SFRXETH).convertToShares(_amount);
			uint256 nftId = IFraxRedemptionQueue(FRAX_QUEUE).enterRedemptionQueueViaSfrxEth(address(this), uint120(sfrxEthAmountNeeded));
			fraxWithdrawalList[fraxTotalWithdrawals++] = nftId;
			emit FraxWithdrawalRequests(nftId);
		}
	}

	/**  
	 * @notice
	 * Internal function that finalises a frax withdrawal. Previously obtained NFT will be consumed in exchange of ether
	 * @return receivedEther Amount of received ether
	 */
	function _finaliseWithdrawExactEthFromFrax() internal returns(uint256 receivedEther) {
		if (fraxCurrentWithdrawalIndex == fraxTotalWithdrawals) return 0;
		uint256 nftId = fraxWithdrawalList[fraxCurrentWithdrawalIndex++];

		receivedEther = address(this).balance;
		IFraxRedemptionQueue(FRAX_QUEUE).burnRedemptionTicketNft(nftId, payable(address(this)));
		receivedEther = address(this).balance - receivedEther;
	}


	/**  
	 * @notice
	 * Internal function that initiates a full frax withdrawal. An nft will be minted on the SEM to be burnt later in exchange of ether
	 */
	function _initiateExitFromFrax() internal {
		uint256 shares = ISfrxEth(SFRXETH).balanceOf(address(this));
		uint256 assets = ISfrxEth(SFRXETH).convertToAssets(shares);

		if (assets > 0) {
			uint256 nftId = IFraxRedemptionQueue(FRAX_QUEUE).enterRedemptionQueueViaSfrxEth(address(this), uint120(shares));
			fraxWithdrawalList[fraxTotalWithdrawals++] = nftId;
			emit FraxWithdrawalRequests(nftId);
		}
	}

	/**  
	 * @notice
	 * Internal function that finalises a full frax withdrawal. Previously obtained NFT will be consumed in exchange of ether
	 */
	function _finaliseExitFromFrax(uint256 _index) internal{
		uint256 nftId = fraxWithdrawalList[_index];

		IFraxRedemptionQueue(FRAX_QUEUE).burnRedemptionTicketNft(nftId, payable(address(this)));
	}
}