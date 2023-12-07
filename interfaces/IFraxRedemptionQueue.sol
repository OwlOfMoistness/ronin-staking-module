// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */


interface IFraxRedemptionQueue {
	function enterRedemptionQueueViaSfrxEth(address _recipient, uint120 _sfrxEthAmount) external returns (uint256 _nftId);
	function burnRedemptionTicketNft(uint256 _nftId, address payable _recipient) external;
}

