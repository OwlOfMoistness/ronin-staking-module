// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "@openzeppelin/token/ERC20/IERC20.sol";

interface IwstETH is IERC20 {
	// deposit by sending eth to this contract
	function unwrap(uint256 _wstETHAmount) external returns (uint256);
	function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
	function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
}