// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */


interface IBridgeManager {
	function getBridgeOperatorWeight(address operator) external view returns (uint256 weight);
	function getTotalWeight() external view returns (uint256 totalWeight);
}
