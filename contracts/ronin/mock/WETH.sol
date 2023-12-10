pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "@openzeppelin/token/ERC20/ERC20.sol";

contract WETH is ERC20("", "") {
	function mint(address to, uint256 amount) external {
		_mint(to, amount);
	}
}