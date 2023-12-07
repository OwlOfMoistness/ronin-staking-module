// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "@openzeppelin/token/ERC20/IERC20.sol";

interface ISfrxEth is IERC20 {
	function convertToAssets(uint256 shares) external view returns (uint256);
	function convertToShares(uint256 assets) external view returns (uint256);
}

