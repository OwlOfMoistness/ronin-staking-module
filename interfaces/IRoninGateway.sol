// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

interface IRoninGateway {
	function requestEther(uint256 _amount) external;
	function getContract(uint8) external view returns(address);
}