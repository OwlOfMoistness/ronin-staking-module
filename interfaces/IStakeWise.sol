// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

interface IStakeWise {
	function enterExitQueue(uint256 shares, address receiver) external returns (uint256 positionTicket);
	function redeem(uint256 shares, address receiver) external returns (uint256 assets);
	function claimExitedAssets(
		uint256 positionTicket,
		uint256 timestamp,
		uint256 exitQueueIndex
	) external returns (uint256 newPositionTicket, uint256 claimedShares, uint256 claimedAssets);
	function deposit(address receiver, address referrer) external payable returns (uint256 shares);
	function convertToAssets(uint256 shares) external view returns (uint256 assets);
	function getExitQueueIndex(uint256 positionTicket) external view returns (int256);
	function totalAssets() external view returns (uint256);
	function getShares(address account) external view returns (uint256);
}