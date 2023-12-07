// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */


interface IFraxEthMinter {
	function submitAndDeposit(address recipient) external payable returns (uint256 shares);
}